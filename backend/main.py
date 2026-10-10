"""

AI Photo Studio - Professional FastAPI Image Generation Backend

Local development:

    python -m uvicorn main:app --host 0.0.0.0 --port 8000

Required environment variables:

    OPENAI_API_KEY=...

Optional:

    OPENAI_MODEL=gpt-image-2.5-sunburst

    OPENAI_SIZE=1024x1536

    OPENAI_TIMEOUT=240

    MAX_UPLOAD_MB=20

This backend:

- accepts Android images even when Android reports application/octet-stream

- normalizes input images safely

- creates a conservative face-protection mask for identity-sensitive edits

- sends the original image + RGBA mask to the OpenAI Image Edits API

- uses template-specific editing instructions

- stores test outputs locally

- returns an absolute output URL

- maps common provider errors to useful HTTP responses

IMPORTANT:

The mask is guidance, not a pixel-perfect guarantee. The model can make

changes around mask boundaries. This is a development/test backend and

should not be exposed publicly without authentication, rate limiting,

persistent storage, and abuse controls.

"""

from __future__ import annotations

import base64

import asyncio

import hashlib

import io

import logging

import os

import uuid

from pathlib import Path

from typing import Final

import cv2

import httpx

import numpy as np

from dotenv import load_dotenv

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile

from fastapi.responses import FileResponse, Response

from pydantic import BaseModel, Field

from PIL import Image, ImageDraw, ImageFilter

import firebase_admin

from firebase_admin import auth as firebase_auth

from firebase_admin import credentials, firestore, storage

from apple_iap import (
    AppleIapConfig,
    duplicate_purchase_action,
    validate_transaction_claims,
    verify_apple_transaction,
)

load_dotenv()

# ---------------------------------------------------------------------------

# Firebase Admin SDK

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------

# Firebase Admin SDK

# ---------------------------------------------------------------------------

FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv(

    "FIREBASE_SERVICE_ACCOUNT_JSON",

)

FIREBASE_STORAGE_BUCKET = os.getenv(

    "FIREBASE_STORAGE_BUCKET",

    "ai-note-scanner.firebasestorage.app",

).strip()

if FIREBASE_SERVICE_ACCOUNT_JSON:

    FIREBASE_SERVICE_ACCOUNT_JSON = FIREBASE_SERVICE_ACCOUNT_JSON.strip()

    if not os.path.exists(FIREBASE_SERVICE_ACCOUNT_JSON):

        raise RuntimeError(

            "Firebase service account file not found: "

            f"{FIREBASE_SERVICE_ACCOUNT_JSON}"

        )

    if not firebase_admin._apps:

        firebase_cred = credentials.Certificate(

            FIREBASE_SERVICE_ACCOUNT_JSON

        )

        firebase_admin.initialize_app(

            firebase_cred,

            {

                "storageBucket": FIREBASE_STORAGE_BUCKET,

            },

        )

else:

    # Cloud Run uses its attached service account through

    # Application Default Credentials.

    if not firebase_admin._apps:

        firebase_admin.initialize_app(

            options={

                "storageBucket": FIREBASE_STORAGE_BUCKET,

            }

        )

db = firestore.client()

bucket = storage.bucket()

# ---------------------------------------------------------------------------

# Configuration

# ---------------------------------------------------------------------------

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-image-2.5-sunburst").strip()

# Pin image edits to medium quality instead of honoring stale low overrides.

OPENAI_QUALITY = "medium"

OPENAI_SIZE = os.getenv("OPENAI_SIZE", "1024x1536").strip()

OPENAI_TIMEOUT = float(os.getenv("OPENAI_TIMEOUT", "240"))

MAX_UPLOAD_MB = int(os.getenv("MAX_UPLOAD_MB", "20"))

GENERATION_COST = 10

AD_REWARD_CREDITS = 5

ALLOWED_QUALITIES: Final = {"low", "medium", "high", "xhigh", "max", "auto"}

ALLOWED_SIZES: Final = {

    "auto",

    "1024x1024",

    "1024x1536",

    "1536x1024",

    "2048x2048",

    "2048x1152",

    "1152x2048",

}

OUTPUT_DIR = Path("test_outputs")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

if not OPENAI_API_KEY:

    raise RuntimeError("OPENAI_API_KEY is missing from .env")

if OPENAI_QUALITY not in ALLOWED_QUALITIES:

    raise RuntimeError(

        f"OPENAI_QUALITY must be one of {sorted(ALLOWED_QUALITIES)}"

    )

if OPENAI_SIZE not in ALLOWED_SIZES:

    raise RuntimeError(

        f"OPENAI_SIZE must be one of {sorted(ALLOWED_SIZES)}"

    )

logging.basicConfig(

    level=logging.INFO,

    format="%(asctime)s | %(levelname)s | %(message)s",

)

logger = logging.getLogger("ai-photo-studio")

app = FastAPI(

    title="AI Photo Studio API",

    version="2.1.0-credits",

)

# ---------------------------------------------------------------------------

# Template policies

# ---------------------------------------------------------------------------

# Templates where clothing is the primary edit. The face/background are

# protected as much as possible.

CLOTHING_ONLY_TEMPLATES: Final = {

    "luxury_black_suit",

    "ceo_portrait",

    "linkedin_professional",

    "corporate_ceo",

    "startup_founder",

    "business_magazine",

    "royal_indian",

    "traditional_kurta",

    "wedding_look",

    "festival_portrait",

}

# Templates where the environment should also be changed. The mask still

# protects detected faces, while allowing the surrounding scene to change.

SCENE_EDIT_TEMPLATES: Final = {

    "luxury_car",

    "night_city_luxury",

    "cinematic_poster",

    "dark_action_hero",

    "hollywood_portrait",

    "crime_thriller",

    "instagram_trending",

    "travel_influencer",

    "birthday_poster",

}

# Couple edits need a wider edit region but should still protect detected

# faces when possible.

COUPLE_TEMPLATES: Final = {"couple_cinematic"}

# ---------------------------------------------------------------------------

# Health / diagnostics

# ---------------------------------------------------------------------------

@app.get("/health")

async def health() -> dict:

    return {

        "status": "ok",

        "service": "ai-photo-studio",

        "version": "2.0.0",

        "model": OPENAI_MODEL,

        "quality": OPENAI_QUALITY,

        "size": OPENAI_SIZE,

        "openai_key_configured": bool(OPENAI_API_KEY),

    }

# ---------------------------------------------------------------------------

# Image preparation

# ---------------------------------------------------------------------------

def decode_source_image(

    image_bytes: bytes,

    filename: str | None,

    content_type: str | None,

) -> Image.Image:

    """Decode Android/gallery input without trusting its MIME type."""

    if not image_bytes:

        raise HTTPException(400, "Uploaded image is empty.")

    max_bytes = MAX_UPLOAD_MB * 1024 * 1024

    if len(image_bytes) > max_bytes:

        raise HTTPException(

            413,

            f"Uploaded image is larger than {MAX_UPLOAD_MB} MB.",

        )

    try:

        image = Image.open(io.BytesIO(image_bytes))

        image.load()

    except Exception as exc:

        raise HTTPException(

            400,

            (

                "The uploaded file is not a supported image. "

                f"filename={filename!r}, content_type={content_type!r}, "

                f"decoder_error={exc}"

            ),

        ) from exc

    # EXIF orientation is intentionally normalized by transposing through

    # Pillow's ImageOps in the production version if needed. For the local

    # test path, keep the decoded pixel dimensions stable.

    if image.mode in ("RGBA", "LA", "P"):

        rgba = image.convert("RGBA")

        background = Image.new("RGB", rgba.size, "white")

        background.paste(rgba, mask=rgba.getchannel("A"))

        image = background

    else:

        image = image.convert("RGB")

    # Prevent extreme memory usage from unusual source dimensions.

    max_dimension = 4096

    if max(image.size) > max_dimension:

        scale = max_dimension / max(image.size)

        new_size = (

            max(1, int(image.width * scale)),

            max(1, int(image.height * scale)),

        )

        image = image.resize(new_size, Image.Resampling.LANCZOS)

    return image

def image_to_jpeg_bytes(image: Image.Image) -> bytes:

    output = io.BytesIO()

    image.save(

        output,

        format="JPEG",

        quality=97,

        subsampling=0,

        optimize=True,

    )

    return output.getvalue()

# ---------------------------------------------------------------------------

# Face detection and mask creation

# ---------------------------------------------------------------------------

def detect_faces(image: Image.Image) -> list[tuple[int, int, int, int]]:

    """

    Detect frontal faces using OpenCV's bundled Haar cascade.

    This is deliberately conservative: failure to detect a face does not

    silently create a dangerous unrestricted clothing mask.

    """

    rgb = np.asarray(image)

    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)

    gray = cv2.equalizeHist(gray)

    cascade_path = (

        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

    )

    detector = cv2.CascadeClassifier(cascade_path)

    if detector.empty():

        raise RuntimeError(

            "OpenCV face detector could not load haarcascade_frontalface_default.xml"

        )

    min_side = max(48, min(image.width, image.height) // 12)

    faces = detector.detectMultiScale(

        gray,

        scaleFactor=1.08,

        minNeighbors=6,

        minSize=(min_side, min_side),

    )

    return [tuple(map(int, face)) for face in faces]

def _expanded_face_box(

    box: tuple[int, int, int, int],

    width: int,

    height: int,

) -> tuple[int, int, int, int]:

    x, y, w, h = box

    # Expand upward substantially to protect hair/head and downward enough

    # to avoid cutting through the jaw/neck during clothing edits.

    left = int(w * 0.22)

    right = int(w * 0.22)

    top = int(h * 0.42)

    bottom = int(h * 0.30)

    x1 = max(0, x - left)

    y1 = max(0, y - top)

    x2 = min(width, x + w + right)

    y2 = min(height, y + h + bottom)

    return x1, y1, x2, y2

def create_edit_mask(

    image: Image.Image,

    template_id: str,

    faces: list[tuple[int, int, int, int]],

) -> bytes:

    """

    Create an RGBA mask.

    OpenAI's edit API uses the transparent portion as the intended edit area.

    We therefore start fully protected (opaque) and make only the intended

    edit region transparent.

    The mask is feathered to avoid a harsh boundary around the face.

    """

    width, height = image.size

    # Alpha 255 = protected.

    mask = Image.new("L", (width, height), 255)

    draw = ImageDraw.Draw(mask)

    if template_id in CLOTHING_ONLY_TEMPLATES:

        # Clothing starts below the face/neck. For each detected face, begin

        # the edit area below its expanded protection box.

        edit_start = int(height * 0.48)

        if faces:

            lowest_protected_y = max(

                _expanded_face_box(face, width, height)[3]

                for face in faces

            )

            edit_start = min(height - 1, max(edit_start, lowest_protected_y))

        # Keep a small shoulder margin protected around the face transition,

        # then allow the lower body/clothing area to be edited.

        draw.rectangle(

            (0, min(height, edit_start), width, height),

            fill=0,

        )

    elif template_id in SCENE_EDIT_TEMPLATES:

        # Scene edits can modify most of the image, but face/head regions

        # remain protected.

        mask = Image.new("L", (width, height), 0)

        draw = ImageDraw.Draw(mask)

        # Protect detected faces/head with soft elliptical regions.

        for face in faces:

            x1, y1, x2, y2 = _expanded_face_box(face, width, height)

            draw.ellipse((x1, y1, x2, y2), fill=255)

    elif template_id in COUPLE_TEMPLATES:

        # Protect all detected faces, edit the surrounding composition.

        mask = Image.new("L", (width, height), 0)

        draw = ImageDraw.Draw(mask)

        for face in faces:

            x1, y1, x2, y2 = _expanded_face_box(face, width, height)

            draw.ellipse((x1, y1, x2, y2), fill=255)

    else:

        # Unknown template: safest behavior is to protect faces and edit the

        # lower half rather than silently performing a full-image rewrite.

        draw.rectangle(

            (0, int(height * 0.52), width, height),

            fill=0,

        )

    # Feather the transition so the model gets a natural editing boundary.

    feather_radius = max(6, min(width, height) // 80)

    mask = mask.filter(ImageFilter.GaussianBlur(feather_radius))

    # Convert grayscale alpha guidance to RGBA. RGB is irrelevant for the

    # mask; alpha is what matters.

    rgba = Image.new("RGBA", (width, height), (255, 255, 255, 255))

    rgba.putalpha(mask)

    output = io.BytesIO()

    rgba.save(output, format="PNG")

    return output.getvalue()

# ---------------------------------------------------------------------------

# Prompt construction

# ---------------------------------------------------------------------------

TEMPLATE_PROMPT_PROFILES = {

    "luxury_black_suit": """

Create a premium luxury fashion portrait. Dress the same person in a perfectly

tailored matte-black or deep-black suit, crisp white dress shirt and elegant

black tie. The suit must fit naturally to the person's existing body.

Use a sophisticated dark charcoal studio environment with subtle architectural

depth, controlled cinematic rim lighting and a soft key light on the face.

Luxury menswear editorial photography, realistic wool texture, precise lapels,

natural fabric folds, refined contrast, premium commercial photography.

No logos, jewelry, sunglasses or unnecessary accessories.

""",

    "ceo_portrait": """

Create a premium executive portrait of the same person. Dress the person in

refined modern business attire with a tailored dark suit and understated shirt.

Place them in an upscale executive office with a softly blurred background.

Use balanced studio-quality lighting, natural skin texture and a confident,

approachable professional presence. Corporate editorial photography with

realistic materials, subtle depth of field and polished composition.

""",

    "luxury_car": """

Create a premium automotive lifestyle portrait. Keep the same person and place

them naturally beside a sophisticated high-end performance car. The person

should wear refined contemporary luxury clothing appropriate for an automotive

campaign. Use a realistic premium location, elegant reflections, believable

perspective and golden-hour cinematic lighting. The car must have physically

correct proportions and reflections. High-end automotive advertising

photography, photorealistic and tasteful.

""",

    "night_city_luxury": """

Create a premium nighttime fashion portrait of the same person in a modern

city environment. Dress the person in sophisticated luxury evening clothing.

Use realistic urban architecture, subtle neon and warm practical lights,

wet-surface reflections only where appropriate, controlled cinematic lighting

and shallow depth of field. The face must remain naturally exposed and sharp.

Luxury editorial street photography, sophisticated and photorealistic.

""",

    "cinematic_poster": """

Create a dramatic cinematic hero portrait of the same person. Give the person

refined cinematic wardrobe appropriate to a serious feature-film lead.

Build a rich atmospheric environment with controlled practical lighting,

subtle haze and strong but realistic depth. Use professional film-still

composition, natural skin texture, believable shadows and restrained cinematic

color grading. Do not add poster text, titles, logos or credits.

""",

    "dark_action_hero": """

Create a sophisticated action-film character portrait of the same person.

Use practical, realistic clothing with subtle rugged styling, dramatic

directional lighting and a dark atmospheric environment. Add restrained

environmental haze and cinematic depth without obscuring the face. The result

should resemble a high-budget film still, with realistic skin, clothing,

lighting and anatomy. No weapons, blood, gore or graphic violence.

""",

    "hollywood_portrait": """

Create a timeless premium film-editorial portrait of the same person. Use

elegant wardrobe, refined studio lighting, subtle warm cinematic tones and a

tasteful sophisticated background. The image should feel like professional

red-carpet/editorial photography rather than an artificial glamour filter.

Preserve natural skin texture, realistic facial detail and believable

proportions. Subtle photographic grain is acceptable.

""",

    "crime_thriller": """

Create a sophisticated neo-noir thriller portrait of the same person. Use

tailored dark clothing, a realistic rain-lit or nighttime urban environment,

controlled practical lights and restrained shadows. Keep the face clearly

visible and naturally exposed. Use cinematic framing, realistic reflections,

subtle atmospheric depth and premium film-still photography. No weapons,

blood, gore, criminal symbols or graphic content.

""",

    "linkedin_professional": """

Create a clean premium professional headshot of the same person. Dress them

in tasteful smart business-casual clothing appropriate for LinkedIn. Use a

clean neutral or softly warm professional background, flattering but natural

soft lighting, realistic skin texture and an approachable confident expression.

Keep the framing head-and-shoulders or upper torso, with sharp facial detail

and minimal visual distraction. Authentic corporate photography.

""",

    "corporate_ceo": """

Create a polished corporate leadership portrait of the same person. Dress them

in a precisely fitted professional business suit with understated styling.

Place them in a modern executive office with a softly blurred architectural

background. Use balanced key and fill lighting, natural posture, realistic

skin texture and a confident but approachable expression. Premium corporate

annual-report/editorial photography.

""",

    "startup_founder": """

Create a modern startup-founder portrait of the same person. Dress them in

smart contemporary founder style: refined smart-casual clothing that looks

credible and understated. Place them in a premium modern workspace with

subtle technology and architectural details in the background. Use natural

window light combined with professional fill, authentic posture and realistic

skin and materials. Modern business editorial photography.

""",

    "business_magazine": """

Create a high-end business magazine editorial portrait of the same person.

Use sophisticated executive or contemporary business styling and a premium

studio/editorial environment. Sculpt the scene with controlled professional

lighting, subtle background separation and realistic material detail. The

composition should feel suitable for a major business publication while

remaining natural and believable. Do not add magazine text, headlines or

logos.

""",

    "royal_indian": """

Create an elegant premium Indian royal portrait of the same person. Dress them

in tasteful, luxurious traditional Indian attire with realistic embroidery,

rich but restrained textiles and refined styling. Use a sophisticated

palace-inspired interior with believable architectural details and warm

cinematic lighting. Preserve natural skin texture and dignified posture.

Luxury Indian fashion editorial photography; elegant rather than costume-like.

Avoid excessive jewelry or artificial embellishment.

""",

    "traditional_kurta": """

Dress the same person in a beautifully tailored traditional Indian kurta with

premium realistic fabric and subtle refined detailing. Use a tasteful warm

Indian festive or architectural setting with soft natural light. Keep the

styling authentic, contemporary and elegant rather than theatrical. Preserve

natural skin texture, realistic fabric folds and comfortable proportions.

Premium Indian lifestyle photography.

""",

    "wedding_look": """

Create a refined premium Indian wedding portrait of the same person. Dress

them in elegant wedding-appropriate traditional attire with realistic,

high-quality fabric, embroidery and restrained accessories. Use sophisticated

warm decorative lighting and an upscale wedding environment with tasteful

depth of field. The result should look like professional luxury wedding

photography, with natural skin, believable clothing and dignified styling.

Avoid excessive retouching and clutter.

""",

    "festival_portrait": """

Create a joyful but premium Indian festival portrait of the same person.

Dress them in tasteful colorful traditional clothing with realistic textiles

and subtle festive details. Use elegant decorative lights and a believable

Indian celebration setting. Keep the colors vibrant but photographic, not

oversaturated. Preserve natural skin texture and create a warm, authentic,

professional festival portrait.

""",

    "instagram_trending": """

Create a polished contemporary social-media creator portrait of the same

person. Use tasteful current fashion styling, a visually clean modern

environment and flattering natural or editorial lighting. The image should

feel premium and current without becoming an exaggerated social-media filter.

Use realistic skin texture, crisp subject detail, controlled background blur

and strong vertical composition suitable for a social profile.

Do not add text, UI elements or platform logos.

""",

    "travel_influencer": """

Create a premium travel-editorial portrait of the same person in a beautiful

realistic destination environment. Use contemporary travel styling appropriate

to the location, natural daylight and believable environmental perspective.

Keep the person as the clear subject while showing enough destination context

to communicate travel. Use realistic atmospheric depth, natural skin and

professional travel-magazine photography.

""",

    "birthday_poster": """

Create a premium birthday celebration portrait of the same person. Use elegant

balloons and tasteful celebratory decorations with realistic materials and

soft studio-quality lighting. Keep the person as the primary subject and use

a polished festive composition with natural skin and realistic depth.

The design should feel like a luxury birthday portrait rather than a cheap

party graphic. Do not add text, numbers, logos or watermarks unless explicitly

requested by the user.

""",

    "couple_cinematic": """

Create a warm cinematic couple portrait using the people present in the

reference image. Preserve each person's identity, facial structure and

natural proportions. Create a tasteful affectionate pose that feels candid

and believable, with coordinated but natural wardrobe. Use soft golden-hour

or cinematic practical lighting, realistic environment and premium editorial

photography. Do not merge faces, duplicate people or invent additional

people. Keep both subjects recognizable.

""",

}

def build_professional_prompt(

    template_id: str,

    template_prompt: str,

    negative_prompt: str,

    face_count: int,

) -> str:

    profile = TEMPLATE_PROMPT_PROFILES.get(

        template_id,

        "Create a premium photorealistic portrait using the requested template.",

    )

    if face_count:

        mask_instruction = """

A face-protection mask is provided. The source face, ears, hairline and hair

are locked. Preserve their appearance exactly: do not change the identity,

expression, smile, gaze, skin tone, facial structure, or hair. Do not redraw,

replace, regenerate, retouch, smooth, beautify, sharpen, relight, recolor or

apply makeup to those regions. Never add a smile or change the source mouth or

teeth. If any template direction conflicts with this lock, preserve the source.

"""

    else:

        mask_instruction = """

No face was detected by the local face detector. Treat the uploaded source

image itself as the identity reference and make only the explicitly requested

transformation. Do not invent a new person.

"""

    return f"""

PROFESSIONAL IMAGE EDITING INSTRUCTION

TASK

Edit the provided photograph into the requested template.

This is an image-editing task, NOT a request to generate a different person.

IDENTITY PRESERVATION — HIGHEST PRIORITY

The uploaded photograph is the authoritative identity reference.

The final image must clearly look like the SAME PERSON.

Preserve whenever visible:

- facial identity and overall likeness

- face shape and facial proportions

- eyes and eye spacing

- eyelids and eyebrows

- nose shape and proportions

- lips and mouth shape

- jawline, cheeks and chin

- ears

- natural skin tone and complexion

- apparent age

- natural facial asymmetry

- hairline and hairstyle unless the template explicitly requests a change

- body proportions

- recognizable expression unless a different expression is explicitly requested

{mask_instruction}

ABSOLUTE FACE LOCK — applies to every template

Keep the exact source facial expression, mouth position and teeth. Never add a

smile. Do not change the face, skin, eyes, ears, hairline or hairstyle. Apply

the requested style only outside protected face and head regions.

EDIT SCOPE

Change only the visual elements required by the selected template.

Do not regenerate the entire person unnecessarily.

Do not turn the source person into a generic AI model.

Do not make the person resemble a celebrity or another individual.

Do not alter ethnicity, age, facial structure or skin tone.

SELECTED TEMPLATE

{template_id}

PROFESSIONAL TEMPLATE DIRECTION

{profile}

SOURCE TEMPLATE DESCRIPTION

{template_prompt}

PHOTOGRAPHIC REALISM

Create a high-end professional photograph:

- physically believable lighting

- realistic skin texture and pores

- accurate facial detail

- realistic fabric, stitching, folds and material response

- natural anatomy and body proportions

- believable shadows and reflections

- realistic lens perspective

- controlled depth of field

- premium commercial/editorial photography

- subtle, tasteful color grading

- clean professional composition

AVOID

- plastic or waxy skin

- excessive face smoothing

- AI beauty-filter appearance

- distorted anatomy

- warped clothing

- duplicated objects or people

- malformed hands or fingers

- unnatural eyes

- inconsistent lighting

- floating objects

- fake-looking backgrounds

- excessive HDR

- cartoon, illustration or CGI appearance

- text, captions, logos or watermarks

EDIT BOUNDARY

Areas not required for the transformation should remain as close as possible

to the source photograph. Protected facial regions must remain consistent with

the source identity.

USER NEGATIVE CONSTRAINTS

{negative_prompt}

FINAL QUALITY CHECK

Before returning the image, prioritize:

1. recognizable identity,

2. natural anatomy,

3. realistic photography,

4. correct template styling,

5. believable lighting and materials.

The final result should look like a professionally photographed version of

the original person, not a newly generated person.

""".strip()

# ---------------------------------------------------------------------------

# OpenAI request

# ---------------------------------------------------------------------------

async def call_openai(

    source_bytes: bytes,

    mask_bytes: bytes,

    prompt: str,

) -> bytes:

    data = {

        "model": OPENAI_MODEL,

        "prompt": prompt,

        "quality": OPENAI_QUALITY,

        "size": OPENAI_SIZE,

        "output_format": "jpeg",

        "output_compression": "90",

    }

    files = {

        "image": ("input.jpg", source_bytes, "image/jpeg"),

        "mask": ("mask.png", mask_bytes, "image/png"),

    }

    logger.info(

        "OpenAI edit | model=%s quality=%s size=%s",

        OPENAI_MODEL,

        OPENAI_QUALITY,

        OPENAI_SIZE,

    )

    async with httpx.AsyncClient(

        timeout=httpx.Timeout(

            connect=20.0,

            read=OPENAI_TIMEOUT,

            write=60.0,

            pool=20.0,

        )

    ) as client:

        response = await client.post(

            "https://api.openai.com/v1/images/edits",

            headers={

                "Authorization": f"Bearer {OPENAI_API_KEY}",

            },

            data=data,

            files=files,

        )

    logger.info("OpenAI response HTTP %s", response.status_code)

    if response.status_code >= 400:

        text = response.text[:6000]

        # Flutter already treats 402 as "need more credits".

        # Convert OpenAI insufficient_quota into that response.

        if (

            response.status_code == 429

            and (

                "insufficient_quota" in text

                or "credit_balance_exhausted" in text

                or "no credits remaining" in text.lower()

            )

        ):

            raise HTTPException(

                402,

                "Your AI generation credits are exhausted. Please add credits.",

            )

        if response.status_code == 429:

            raise HTTPException(

                429,

                "The image service is temporarily rate-limited. Please try again shortly.",

            )

        if response.status_code in (401, 403):

            raise HTTPException(

                502,

                "The image service rejected the API credentials or organization access.",

            )

        raise HTTPException(

            502,

            f"OpenAI image edit failed ({response.status_code}). Details: {text}",

        )

    try:

        payload = response.json()

        b64 = payload["data"][0]["b64_json"]

        return base64.b64decode(b64)

    except Exception as exc:

        raise HTTPException(

            502,

            f"OpenAI returned an unexpected image response: {exc}",

        ) from exc

# ---------------------------------------------------------------------------

# Authentication

# ---------------------------------------------------------------------------

def verify_firebase_user(

    authorization: str | None,

) -> dict:

    """Verify a Firebase ID token and return its decoded claims."""

    if not authorization:

        raise HTTPException(

            status_code=401,

            detail="Missing Authorization header.",

        )

    if not authorization.startswith("Bearer "):

        raise HTTPException(

            status_code=401,

            detail="Invalid Authorization header.",

        )

    token = authorization[7:].strip()

    if not token:

        raise HTTPException(

            status_code=401,

            detail="Missing Firebase ID token.",

        )

    try:

        return firebase_auth.verify_id_token(token)

    except Exception as exc:

        logger.warning("Firebase authentication failed: %s", exc)

        raise HTTPException(

            status_code=401,

            detail="Invalid or expired Firebase authentication token.",

        ) from exc

# ---------------------------------------------------------------------------

# User profile

# ---------------------------------------------------------------------------

@app.get("/v1/profile")

async def get_profile(

    authorization: str | None = Header(default=None),

):

    """Return the authenticated user's photo-studio profile.

    The backend creates the profile with the initial 5 credits the first

    time the user calls this endpoint. Flutter cannot write this document

    because Firestore client rules deny create/update/delete.

    """

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    user_ref = db.collection("users").document(uid)

    user_snapshot = user_ref.get()

    if not user_snapshot.exists:

        user_data = {

            "credits": 5,

            "plan": "free",

            "totalGenerations": 0,

            "createdAt": firestore.SERVER_TIMESTAMP,

            "updatedAt": firestore.SERVER_TIMESTAMP,

        }

        user_ref.set(user_data)

        logger.info(

            "Created new photo-studio profile | uid=%s | credits=5",

            uid,

        )

        return {

            "success": True,

            "uid": uid,

            "credits": 5,

            "plan": "free",

            "totalGenerations": 0,

        }

    data = user_snapshot.to_dict() or {}

    # Keep non-sensitive Google profile metadata synchronized for the VYRO

    # profile screen. Firebase ID-token claims are server-verified above.

    profile_updates = {}

    for claim_key, field_name in (("name", "displayName"), ("email", "email"), ("picture", "photoUrl")):

        value = decoded_token.get(claim_key)

        if value:

            profile_updates[field_name] = value

    if profile_updates:

        profile_updates["updatedAt"] = firestore.SERVER_TIMESTAMP

        user_ref.set(profile_updates, merge=True)

        data.update(profile_updates)

    return {

        "success": True,

        "uid": uid,

        "credits": int(data.get("credits", 0)),

        "plan": data.get("plan", "free"),

        "totalGenerations": int(data.get("totalGenerations", 0)),

        "displayName": data.get("displayName"),

        "email": data.get("email"),

        "photoUrl": data.get("photoUrl"),

        "isAnonymous": bool(decoded_token.get("firebase", {}).get("sign_in_provider") == "anonymous"),

    }

# ---------------------------------------------------------------------------

# Credits and rewards

# ---------------------------------------------------------------------------

def _get_or_create_profile_ref(uid: str):

    return db.collection("users").document(uid)


class ApplePurchaseVerificationRequest(BaseModel):

    signedTransactionJws: str = Field(min_length=1, max_length=32768)


@app.post("/v1/iap/apple/verify")
async def verify_apple_purchase(
    payload: ApplePurchaseVerificationRequest,
    authorization: str | None = Header(default=None),
):

    """Verify an Apple-signed transaction and grant its credit pack once."""

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    try:

        config = AppleIapConfig.from_environment(os.environ)

    except (RuntimeError, ValueError) as exc:

        logger.error("Apple IAP verification configuration is incomplete.")

        raise HTTPException(

            status_code=503,

            detail="Apple purchase verification is not configured. Please try again later.",

        ) from exc

    try:

        verified_claims, environment = await asyncio.to_thread(

            verify_apple_transaction,

            payload.signedTransactionJws,

            config,

        )

        grant = validate_transaction_claims(

            verified_claims,

            uid=uid,

            bundle_id=config.bundle_id,

        )

    except ValueError as exc:

        logger.warning("Apple IAP rejected a verified transaction: %s", exc)

        raise HTTPException(status_code=400, detail=str(exc)) from exc

    except RuntimeError as exc:

        logger.warning("Apple IAP could not confirm transaction status.")

        raise HTTPException(

            status_code=503,

            detail="Apple could not confirm the transaction status. Please retry.",

        ) from exc

    is_sandbox = environment.lower() == "sandbox"

    if is_sandbox and uid not in config.sandbox_uid_allowlist:

        logger.warning("Apple sandbox purchase rejected for a non-allowlisted account.")

        raise HTTPException(

            status_code=403,

            detail="Sandbox purchases are not enabled for this account.",

        )

    grant["environment"] = environment

    purchase_key = hashlib.sha256(grant["transaction_id"].encode("utf-8")).hexdigest()

    purchase_ref = db.collection("apple_iap_transactions").document(purchase_key)

    user_ref = _get_or_create_profile_ref(uid)

    purchase_transaction = db.transaction()

    @firestore.transactional

    def apply_credit_grant(transaction):

        purchase_snapshot = purchase_ref.get(transaction=transaction)

        purchase_data = purchase_snapshot.to_dict() if purchase_snapshot.exists else None

        action = duplicate_purchase_action(purchase_data, uid)

        user_snapshot = user_ref.get(transaction=transaction)

        user_data = user_snapshot.to_dict() if user_snapshot.exists else {}

        current_credits = int(user_data.get("credits", 5 if not user_snapshot.exists else 0))

        if action == "already_processed":

            return {

                "duplicate": True,

                "credits": current_credits,

                "credits_added": 0,

            }

        credits_added = int(grant["credits"])

        updated_credits = current_credits + credits_added

        profile_values = {

            "credits": updated_credits,

            "updatedAt": firestore.SERVER_TIMESTAMP,

        }

        if user_snapshot.exists:

            transaction.update(user_ref, profile_values)

        else:

            profile_values.update(

                {

                    "plan": "free",

                    "totalGenerations": 0,

                    "createdAt": firestore.SERVER_TIMESTAMP,

                }

            )

            transaction.create(user_ref, profile_values)

        transaction.create(

            purchase_ref,

            {

                "uid": uid,

                "transactionIdHash": purchase_key,

                "productId": grant["product_id"],

                "credits": credits_added,

                "environment": environment,

                "createdAt": firestore.SERVER_TIMESTAMP,

            },

        )

        return {

            "duplicate": False,

            "credits": updated_credits,

            "credits_added": credits_added,

        }

    try:

        result = apply_credit_grant(purchase_transaction)

    except ValueError as exc:

        logger.warning("Apple IAP transaction ownership conflict.")

        raise HTTPException(status_code=409, detail=str(exc)) from exc

    except Exception as exc:

        logger.exception("Apple IAP credit grant failed.")

        raise HTTPException(

            status_code=500,

            detail="Verified purchase could not be added yet. Please retry.",

        ) from exc

    logger.info(

        "Apple IAP processed | transaction=%s | product=%s | duplicate=%s",

        purchase_key[:12],

        grant["product_id"],

        result["duplicate"],

    )

    return {

        "success": True,

        "duplicate": result["duplicate"],

        "creditsAdded": result["credits_added"],

        "credits": result["credits"],

        "productId": grant["product_id"],

    }

def reserve_generation_credits(uid: str, request_id: str) -> None:

    """Atomically reserve 10 credits for one generation request."""

    user_ref = _get_or_create_profile_ref(uid)

    attempt_ref = db.collection("generation_attempts").document(request_id)

    transaction = db.transaction()

    @firestore.transactional

    def _reserve(transaction):

        snapshot = user_ref.get(transaction=transaction)

        if not snapshot.exists:

            credits = 5

            transaction.create(

                user_ref,

                {

                    "credits": credits,

                    "plan": "free",

                    "totalGenerations": 0,

                    "createdAt": firestore.SERVER_TIMESTAMP,

                    "updatedAt": firestore.SERVER_TIMESTAMP,

                },

            )

        else:

            data = snapshot.to_dict() or {}

            credits = int(data.get("credits", 0))

        if credits < GENERATION_COST:

            raise HTTPException(

                status_code=402,

                detail="You need 10 credits to create this photo.",

            )

        transaction.update(

            user_ref,

            {

                "credits": credits - GENERATION_COST,

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

        transaction.create(

            attempt_ref,

            {

                "uid": uid,

                "status": "reserved",

                "cost": GENERATION_COST,

                "createdAt": firestore.SERVER_TIMESTAMP,

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

    try:

        _reserve(transaction)

        logger.info(

            "[%s] Reserved %d credits | uid=%s",

            request_id,

            GENERATION_COST,

            uid,

        )

    except HTTPException:

        raise

    except Exception as exc:

        logger.exception("[%s] Credit reservation failed", request_id)

        raise HTTPException(

            500,

            "Could not reserve generation credits. Please try again.",

        ) from exc

def complete_generation(uid: str, request_id: str) -> None:

    """Mark a reserved generation successful and increment its counter."""

    user_ref = _get_or_create_profile_ref(uid)

    attempt_ref = db.collection("generation_attempts").document(request_id)

    transaction = db.transaction()

    @firestore.transactional

    def _complete(transaction):

        attempt = attempt_ref.get(transaction=transaction)

        if not attempt.exists:

            raise RuntimeError("Generation attempt record does not exist.")

        attempt_data = attempt.to_dict() or {}

        if attempt_data.get("status") == "completed":

            return

        if attempt_data.get("status") != "reserved":

            raise RuntimeError(

                f"Generation attempt is not reservable: {attempt_data.get('status')}"

            )

        user_snapshot = user_ref.get(transaction=transaction)

        if not user_snapshot.exists:

            raise RuntimeError("User profile does not exist.")

        data = user_snapshot.to_dict() or {}

        total = int(data.get("totalGenerations", 0))

        transaction.update(

            user_ref,

            {

                "totalGenerations": total + 1,

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

        transaction.update(

            attempt_ref,

            {

                "status": "completed",

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

    _complete(transaction)

    logger.info("[%s] Generation completed | uid=%s", request_id, uid)

def refund_generation_credits(uid: str, request_id: str) -> None:

    """Refund reserved credits exactly once after a failed generation."""

    user_ref = _get_or_create_profile_ref(uid)

    attempt_ref = db.collection("generation_attempts").document(request_id)

    transaction = db.transaction()

    @firestore.transactional

    def _refund(transaction):

        attempt = attempt_ref.get(transaction=transaction)

        if not attempt.exists:

            return

        attempt_data = attempt.to_dict() or {}

        if attempt_data.get("status") != "reserved":

            return

        user_snapshot = user_ref.get(transaction=transaction)

        if not user_snapshot.exists:

            raise RuntimeError("User profile does not exist for refund.")

        data = user_snapshot.to_dict() or {}

        credits = int(data.get("credits", 0))

        transaction.update(

            user_ref,

            {

                "credits": credits + GENERATION_COST,

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

        transaction.update(

            attempt_ref,

            {

                "status": "refunded",

                "updatedAt": firestore.SERVER_TIMESTAMP,

            },

        )

    _refund(transaction)

    logger.info(

        "[%s] Refunded %d credits after failed generation | uid=%s",

        request_id,

        GENERATION_COST,

        uid,

    )

@app.post("/v1/rewards/ad")

async def reward_ad(

    rewardId: str = Form(...),

    authorization: str | None = Header(default=None),

):

    """Grant +5 credits after Flutter receives AdMob's earned-reward callback.

    Phase 1 uses a one-time rewardId to prevent accidental duplicate grants.

    Production should additionally use AdMob server-side verification (SSV)

    so a modified client cannot forge reward requests.

    """

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    reward_id = rewardId.strip()

    if not reward_id or len(reward_id) > 128:

        raise HTTPException(400, "Invalid reward ID.")

    user_ref = _get_or_create_profile_ref(uid)

    reward_ref = db.collection("ad_rewards").document(reward_id)

    transaction = db.transaction()

    @firestore.transactional

    def _grant(transaction):

        existing = reward_ref.get(transaction=transaction)

        if existing.exists:

            existing_data = existing.to_dict() or {}

            if existing_data.get("uid") != uid:

                raise HTTPException(409, "Reward ID has already been used.")

            return False

        user_snapshot = user_ref.get(transaction=transaction)

        if not user_snapshot.exists:

            transaction.create(

                user_ref,

                {

                    "credits": AD_REWARD_CREDITS,

                    "plan": "free",

                    "totalGenerations": 0,

                    "createdAt": firestore.SERVER_TIMESTAMP,

                    "updatedAt": firestore.SERVER_TIMESTAMP,

                },

            )

        else:

            data = user_snapshot.to_dict() or {}

            credits = int(data.get("credits", 0))

            transaction.update(

                user_ref,

                {

                    "credits": credits + AD_REWARD_CREDITS,

                    "updatedAt": firestore.SERVER_TIMESTAMP,

                },

            )

        transaction.create(

            reward_ref,

            {

                "uid": uid,

                "credits": AD_REWARD_CREDITS,

                "source": "admob_rewarded",

                "status": "granted",

                "createdAt": firestore.SERVER_TIMESTAMP,

            },

        )

        return True

    try:

        granted = _grant(transaction)

    except HTTPException:

        raise

    except Exception as exc:

        logger.exception("Ad reward grant failed | uid=%s", uid)

        raise HTTPException(

            500,

            "Could not grant the ad reward. Please try again.",

        ) from exc

    snapshot = user_ref.get()

    data = snapshot.to_dict() or {}

    credits = int(data.get("credits", 0))

    return {

        "success": True,

        "granted": granted,

        "creditsAwarded": AD_REWARD_CREDITS if granted else 0,

        "credits": credits,

    }

# ---------------------------------------------------------------------------

# Persistent creation storage

# ---------------------------------------------------------------------------

def _creation_document(uid: str, generation_id: str):

    """Return the authenticated user's Firestore generation document."""

    return (

        db.collection("users")

        .document(uid)

        .collection("generations")

        .document(generation_id)

    )

def _safe_storage_path(uid: str, generation_id: str) -> str:

    """Build the only Firebase Storage path used by VYRO."""

    return f"users/{uid}/generations/{generation_id}.png"

def _jpeg_to_png_bytes(image_bytes: bytes) -> bytes:

    """Convert OpenAI's JPEG result to PNG because Flutter validates .png paths."""

    with Image.open(io.BytesIO(image_bytes)) as image:

        rgb = image.convert("RGB")

        output = io.BytesIO()

        rgb.save(output, format="PNG", optimize=True)

        return output.getvalue()

def save_creation(

    uid: str,

    request_id: str,

    output_bytes: bytes,

    template_id: str,

    prompt: str,

    negative_prompt: str,

) -> str:

    """Upload the image and save metadata in the user's Firestore subcollection."""

    storage_path = _safe_storage_path(uid, request_id)

    png_bytes = _jpeg_to_png_bytes(output_bytes)

    blob = bucket.blob(storage_path)

    blob.upload_from_string(png_bytes, content_type="image/png")

    creation_ref = _creation_document(uid, request_id)

    creation_ref.set(

        {

            "generationId": request_id,

            "uid": uid,

            "templateId": template_id,

            "prompt": prompt,

            "negativePrompt": negative_prompt,

            "storagePath": storage_path,

            "createdAt": firestore.SERVER_TIMESTAMP,

            "model": OPENAI_MODEL,

            "creditsUsed": GENERATION_COST,

            "watermark": True,

            "status": "completed",

        }

    )

    return storage_path

@app.get("/v1/my-creations")

async def get_my_creations(

    authorization: str | None = Header(default=None),

):

    """Return authenticated user's creation metadata without signed URLs."""

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    query = (

        db.collection("users")

        .document(uid)

        .collection("generations")

        .order_by("createdAt", direction=firestore.Query.DESCENDING)

        .limit(100)

        .stream()

    )

    items = []

    for doc in query:

        data = doc.to_dict() or {}

        storage_path = data.get("storagePath", "")

        expected_prefix = f"users/{uid}/generations/"

        if not storage_path.startswith(expected_prefix) or ".." in storage_path:

            continue

        items.append({

            "id": data.get("generationId", doc.id),

            "generationId": data.get("generationId", doc.id),

            "templateId": data.get("templateId", ""),

            "storagePath": storage_path,

            "imageUrl": None,

            "createdAt": str(data.get("createdAt", "")),

            "creditsUsed": int(data.get("creditsUsed", GENERATION_COST)),

            "watermark": bool(data.get("watermark", True)),

        })

    return {"success": True, "items": items}

@app.delete("/v1/my-creations/{creation_id}")

async def delete_my_creation(

    creation_id: str,

    authorization: str | None = Header(default=None),

):

    """Delete one authenticated user's creation and its Storage object."""

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    ref = _creation_document(uid, creation_id)

    snapshot = ref.get()

    if not snapshot.exists:

        raise HTTPException(status_code=404, detail="Creation not found.")

    data = snapshot.to_dict() or {}

    if data.get("uid") != uid:

        raise HTTPException(status_code=403, detail="You cannot delete this creation.")

    storage_path = data.get("storagePath", "")

    expected_prefix = f"users/{uid}/generations/"

    if storage_path and storage_path.startswith(expected_prefix) and ".." not in storage_path:

        blob = bucket.blob(storage_path)

        try:

            if blob.exists():

                blob.delete()

        except Exception:

            logger.exception("Failed to delete Storage object | uid=%s | path=%s", uid, storage_path)

    ref.delete()

    return {"success": True, "deleted": creation_id}

@app.get("/v1/my-creations/{creation_id}/watermarked")

async def get_watermarked_creation(

    creation_id: str,

    authorization: str | None = Header(default=None),

):

    """Return a temporary watermarked JPEG for a free user's download."""

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    ref = _creation_document(uid, creation_id)

    snapshot = ref.get()

    if not snapshot.exists:

        raise HTTPException(status_code=404, detail="Creation not found.")

    data = snapshot.to_dict() or {}

    if data.get("uid") != uid:

        raise HTTPException(status_code=403, detail="You cannot access this creation.")

    storage_path = data.get("storagePath", "")

    expected_prefix = f"users/{uid}/generations/"

    if not storage_path.startswith(expected_prefix) or ".." in storage_path:

        raise HTTPException(status_code=400, detail="Invalid creation storage path.")

    try:

        source_bytes = bucket.blob(storage_path).download_as_bytes()

        with Image.open(io.BytesIO(source_bytes)) as source:

            image = source.convert("RGBA")

            draw = ImageDraw.Draw(image, "RGBA")

            text = "VYRO"

            font = None

            font_size = max(18, min(image.width, image.height) // 38)

            try:

                from PIL import ImageFont

                font = ImageFont.load_default(size=font_size)

            except Exception:

                pass

            bbox = draw.textbbox((0, 0), text, font=font)

            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]

            pad_x, pad_y = max(12, font_size // 2), max(8, font_size // 3)

            x = image.width - tw - pad_x * 2 - 12

            y = image.height - th - pad_y * 2 - 12

            draw.rounded_rectangle(

                (x, y, x + tw + pad_x * 2, y + th + pad_y * 2),

                radius=max(8, font_size // 3),

                fill=(0, 0, 0, 150),

            )

            draw.text(

                (x + pad_x, y + pad_y - bbox[1]),

                text,

                fill=(255, 255, 255, 225),

                font=font,

            )

            output = io.BytesIO()

            image.convert("RGB").save(output, format="JPEG", quality=92, optimize=True)

            watermarked = output.getvalue()

        return Response(

            content=watermarked,

            media_type="image/jpeg",

            headers={"Cache-Control": "private, max-age=300"},

        )

    except HTTPException:

        raise

    except Exception as exc:

        logger.exception("Watermarked creation failed | uid=%s | id=%s", uid, creation_id)

        raise HTTPException(500, "Could not prepare the watermarked image.") from exc

@app.post("/v1/generations")
async def create_generation(

    request: Request,

    authorization: str | None = Header(default=None),

    image: UploadFile = File(...),

    templateId: str = Form(...),

    prompt: str = Form(...),

    negativePrompt: str = Form(""),

):

    request_id = uuid.uuid4().hex[:12]

    # Every generation request must come from an authenticated Firebase user.

    decoded_token = verify_firebase_user(authorization)

    uid = decoded_token["uid"]

    # Reserve credits BEFORE any OpenAI work. The reservation is atomic.

    # If generation fails later, the exception handler refunds them exactly once.

    reserve_generation_credits(uid, request_id)

    logger.info(

        "[%s] Authenticated generation request | uid=%s",

        request_id,

        uid,

    )

    logger.info(

        "[%s] Generation requested | template=%s filename=%s mime=%s",

        request_id,

        templateId,

        image.filename,

        image.content_type,

    )

    try:

        raw = await image.read()

        source = decode_source_image(

            raw,

            image.filename,

            image.content_type,

        )

        logger.info(

            "[%s] Source image decoded | size=%sx%s",

            request_id,

            source.width,

            source.height,

        )

        faces = detect_faces(source)

        if not faces:

            logger.warning(

                "[%s] No frontal face detected; continuing with conservative mask.",

                request_id,

            )

        else:

            logger.info(

                "[%s] Detected %d face(s)",

                request_id,

                len(faces),

            )

        source_bytes = image_to_jpeg_bytes(source)

        mask_bytes = create_edit_mask(

            source,

            templateId,

            faces,

        )

        final_prompt = build_professional_prompt(

            templateId,

            prompt,

            negativePrompt,

            len(faces),

        )

        output_bytes = await call_openai(

            source_bytes,

            mask_bytes,

            final_prompt,

        )

        storage_path = save_creation(

            uid=uid,

            request_id=request_id,

            output_bytes=output_bytes,

            template_id=templateId,

            prompt=prompt,

            negative_prompt=negativePrompt,

        )

        complete_generation(uid, request_id)

        logger.info(

            "[%s] Generation successful | storage=%s",

            request_id,

            storage_path,

        )

        return {

            "success": True,

            "requestId": request_id,

            "generationId": request_id,

            "uid": uid,

            "templateId": templateId,

            "storagePath": storage_path,

            "outputImageUrl": None,

            "message": "Photo generated successfully.",

        }

    except HTTPException:

        # A reserved generation is refunded for any HTTP-level failure.

        refund_generation_credits(uid, request_id)

        raise

    except httpx.TimeoutException as exc:

        refund_generation_credits(uid, request_id)

        logger.exception("[%s] OpenAI request timed out", request_id)

        raise HTTPException(

            504,

            "The image service took too long to respond. Please try again.",

        ) from exc

    except httpx.RequestError as exc:

        refund_generation_credits(uid, request_id)

        logger.exception("[%s] OpenAI connection error", request_id)

        raise HTTPException(

            502,

            "Could not connect to the image service. Please try again.",

        ) from exc

    except Exception as exc:

        refund_generation_credits(uid, request_id)

        logger.exception("[%s] Unexpected generation failure", request_id)

        raise HTTPException(

            500,

            f"Generation failed. Request ID: {request_id}",

        ) from exc

# ---------------------------------------------------------------------------

# Local test output

# ---------------------------------------------------------------------------

@app.get("/test-output/{filename}")

async def get_test_output(filename: str):

    # Prevent path traversal.

    safe_name = Path(filename).name

    if safe_name != filename:

        raise HTTPException(400, "Invalid output filename.")

    path = OUTPUT_DIR / safe_name

    if not path.exists() or not path.is_file():

        raise HTTPException(404, "Generated image not found.")

    return FileResponse(

        path,

        media_type="image/jpeg",

        headers={

            "Cache-Control": "no-store",

        },

    )
