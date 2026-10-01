# AI Photo Studio - OpenAI-only test backend

This version does NOT require Firebase Storage or Firestore.
It only tests:

Flutter -> FastAPI -> OpenAI -> local generated image

## Setup

Keep your existing `.venv`.

Install/update dependencies:

```powershell
pip install -r requirements.txt
```

Create `.env`:

```env
OPENAI_API_KEY=sk-your-real-key
OPENAI_MODEL=gpt-image-1-mini
```

Do not share your API key.

Start:

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Health test:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/health
```

Generated test images are saved to:

```text
test_outputs/generated_photo.jpg
```

NOTE:
The model name is configurable. If your OpenAI account/API reports that
`gpt-image-1-mini` is unavailable, change OPENAI_MODEL to a currently
available image model in `.env`.
