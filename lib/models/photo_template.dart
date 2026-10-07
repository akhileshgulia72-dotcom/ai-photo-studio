enum TemplateCategory {
  luxury,
  cinematic,
  professional,
  indian,
  social,
  couple,
  travel,
  creative,
}

class PhotoTemplate {
  const PhotoTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.prompt,
    required this.imagePath,
    this.negativePrompt =
        'changed face, different person, face swap, altered identity, changed expression, changed smile, open mouth, changed teeth, changed eyes, changed nose, changed jaw, changed facial proportions, enlarged face, oversized head, tiny distant face, unnatural head-to-body ratio, changed hairline, changed hairstyle, face reshaping, face slimming, beauty filter, plastic skin, extra fingers, blurry, watermark, text',
    this.isPremium = false,
    // UI hint only; authorization and deduction remain server-controlled.
    this.creditsRequired = 10,
    this.aspectRatio = '4:5',
    this.isTrending = false,
    this.isFeatured = false,
  });
  final String id,
      title,
      description,
      prompt,
      imagePath,
      negativePrompt,
      aspectRatio;
  final TemplateCategory category;
  final bool isPremium, isTrending, isFeatured;
  final int creditsRequired;
  String get categoryLabel => switch (category) {
    TemplateCategory.luxury => 'Luxury',
    TemplateCategory.cinematic => 'Cinematic',
    TemplateCategory.professional => 'Professional',
    TemplateCategory.indian => 'Indian & Festivals',
    TemplateCategory.social => 'Social Media',
    TemplateCategory.couple => 'Couple',
    TemplateCategory.travel => 'Travel',
    TemplateCategory.creative => 'Creative',
  };
}

class TemplateCatalog {
  static const all = <PhotoTemplate>[
    PhotoTemplate(
      id: 'luxury_black_suit',
      imagePath: 'assets/templates/luxury_black_suit.webp',
      title: 'Luxury Black Suit',
      category: TemplateCategory.luxury,
      description:
          'A refined, cinematic fashion portrait with timeless confidence.',
      prompt:
          'Match the cover: relaxed seated luxury menswear portrait, black tailored suit and black shirt, framed from head to knees against a charcoal studio background with soft side light and restrained rim glow. Preserve the uploaded person’s exact face, expression, gaze and hair; never add a smile or retouch the face. No tie, text or logos.',
      isFeatured: true,
      isTrending: true,
    ),
    PhotoTemplate(
      id: 'ceo_portrait',
      imagePath: 'assets/templates/ceo_portrait.webp',
      title: 'CEO Portrait',
      category: TemplateCategory.luxury,
      description:
          'A polished executive portrait with a premium editorial finish.',
      prompt:
          'Match the cover: seated executive at a desk, head to waist, dark blazer over a light blouse or shirt, bright office window and softly blurred skyline, cool daylight and polished corporate editorial style. Preserve face, expression, gaze and hair exactly; no retouching, text or logos.',
    ),
    PhotoTemplate(
      id: 'luxury_car',
      imagePath: 'assets/images/car.png',
      title: 'Luxury Car',
      category: TemplateCategory.luxury,
      description: 'Step into a dramatic automotive campaign.',
      prompt:
          'Create a premium automotive campaign photograph with the uploaded person as the clear primary human subject. Show the same person full-body beside the front quarter of one dark luxury performance car at a modern villa during golden hour. Keep the person large enough to occupy roughly 60–70% of the image height, with the face clearly detailed and recognizable, while keeping realistic head-to-body proportions. Position the person near the left third and let the car extend prominently through the center and right side. Use a wide landscape composition with realistic perspective, natural posture, believable shadows and warm but balanced reflections. Do not enlarge only the face or change facial geometry. Preserve face, expression, gaze, skin texture and hair. No extra cars, text or logos.',
    ),
    PhotoTemplate(
      id: 'night_city_luxury',
      imagePath: 'assets/templates/night_city_luxury.webp',
      title: 'Night City Luxury',
      category: TemplateCategory.luxury,
      description: 'A sophisticated night portrait among city lights.',
      prompt:
          'Match the cover: elegant black evening outfit in a head-to-hips portrait, softly glowing high-rise city lights at night, deep blue-black background and warm bokeh. Preserve the uploaded face, expression, gaze and hair exactly; do not force a new pose, smile or retouching.',
    ),
    PhotoTemplate(
      id: 'cinematic_poster',
      imagePath: 'assets/templates/cinematic_poster.webp',
      title: 'Cinematic Movie Poster',
      category: TemplateCategory.cinematic,
      description: 'A dramatic hero frame with cinematic color and light.',
      prompt:
          'Match the cover: close chest-up rugged cinematic hero portrait, dark practical jacket, smoky charcoal atmosphere, warm amber backlight and cool shadow fill. Keep the uploaded face, expression, gaze, hair and identity exactly unchanged. No full-body reframing, text, titles or logos.',
    ),
    PhotoTemplate(
      id: 'dark_action_hero',
      imagePath: 'assets/templates/dark_action_hero.webp',
      title: 'Dark Action Hero',
      category: TemplateCategory.cinematic,
      description: 'A bold action portrait with moody atmosphere.',
      prompt:
          'Match the cover: tight chest-up action portrait in a dark rain jacket, visible rain, cool blue-gray lighting, wet fabric highlights and a softly blurred stormy background. Keep face unobscured and exactly as uploaded, including expression and hair. No weapons, blood, text or logos.',
    ),
    PhotoTemplate(
      id: 'hollywood_portrait',
      imagePath: 'assets/templates/hollywood_portrait.webp',
      title: 'Hollywood Portrait',
      category: TemplateCategory.cinematic,
      description: 'Red-carpet polish with a timeless film-star look.',
      prompt:
          'Match the cover: red-carpet portrait cropped from head to waist, elegant deep-red evening styling, refined jewelry and softly blurred event lights. Warm polished editorial photography. Preserve the uploaded face, expression, gaze and hair exactly; no beauty retouch, text or logos.',
    ),
    PhotoTemplate(
      id: 'crime_thriller',
      imagePath: 'assets/templates/crime_thriller.webp',
      title: 'Crime Thriller',
      category: TemplateCategory.cinematic,
      description: 'An atmospheric neo-noir character portrait.',
      prompt:
          'Match the cover: chest-up neo-noir portrait in a dark overcoat, smoky amber practical light and deep shadow with a softly glowing night street. A wide-brim hat only if it does not obscure or alter the uploaded face or hair. Preserve expression and identity; no weapons, text or logos.',
    ),
    PhotoTemplate(
      id: 'linkedin_professional',
      imagePath: 'assets/templates/linkedin_professional.webp',
      title: 'LinkedIn Professional',
      category: TemplateCategory.professional,
      description: 'A welcoming, polished profile photo for work.',
      prompt:
          'Match the cover: head-and-shoulders portrait, navy blazer and light blue open-collar shirt, softly blurred green office plants and bright window light. Clean eye-level corporate photography. Preserve face, expression, gaze and hair exactly; no invented smile, text, watermark or logo.',
    ),
    PhotoTemplate(
      id: 'corporate_ceo',
      imagePath: 'assets/templates/corporate_ceo.webp',
      title: 'Corporate CEO',
      category: TemplateCategory.professional,
      description: 'Confident leadership portrait for a company profile.',
      prompt:
          'Match the cover: waist-up corporate portrait in a crisp white blazer and blouse or equivalent light formalwear, bright glass office and soft neutral daylight. Arms crossed only if compatible with the source pose. Preserve face, expression, gaze and hair exactly; no text or logos.',
    ),
    PhotoTemplate(
      id: 'startup_founder',
      imagePath: 'assets/templates/startup_founder.webp',
      title: 'Startup Founder',
      category: TemplateCategory.professional,
      description: 'Modern founder energy in a creative workspace.',
      prompt:
          'Match the cover: relaxed waist-up founder portrait in a dark crew-neck shirt at a laptop, warm modern workspace with softly blurred plants and practical lights. Hand near chin only if compatible with the source pose. Preserve face, expression and hair exactly; no legible screen content or logos.',
    ),
    PhotoTemplate(
      id: 'business_magazine',
      imagePath: 'assets/templates/business_magazine.webp',
      title: 'Business Magazine',
      category: TemplateCategory.professional,
      description: 'An editorial cover-style business portrait.',
      prompt:
          'Match the cover: seated senior-business portrait framed head to lap, charcoal suit, white shirt and dark tie, softly blurred dark office and subtle side light. Keep pose only if compatible with source anatomy. Preserve face, expression, gaze and hair exactly; no magazine headlines or logos.',
    ),
    PhotoTemplate(
      id: 'royal_indian',
      imagePath: 'assets/templates/royal_indian.webp',
      title: 'Royal Indian',
      category: TemplateCategory.indian,
      description: 'Regal Indian-inspired styling with rich details.',
      prompt:
          'Match the cover: seated groom portrait framed from head to lap, embroidered ivory sherwani, deep-red stole and cream turban with a small traditional ornament, against warm candlelit palace decor. Rich ivory, gold and maroon textiles. Preserve face and expression exactly; no text or excessive jewelry.',
      isPremium: true,
    ),
    PhotoTemplate(
      id: 'traditional_kurta',
      imagePath: 'assets/templates/traditional_kurta.webp',
      title: 'Traditional Kurta',
      category: TemplateCategory.indian,
      description: 'A graceful traditional look for a festive occasion.',
      prompt:
          'Match the cover: waist-up portrait in an ivory embroidered kurta, leafy courtyard background and warm natural daylight, with a soft cream-and-green palette. Preserve uploaded face, expression, gaze and hair exactly; no theatrical styling or text.',
    ),
    PhotoTemplate(
      id: 'wedding_look',
      imagePath: 'assets/templates/wedding_look.webp',
      title: 'Wedding Look',
      category: TemplateCategory.indian,
      description: 'A celebration-ready portrait with elegant styling.',
      prompt:
          'Match the cover: waist-up bridal portrait with embroidered red lehenga and dupatta, tasteful traditional jewelry and warm candlelit floral bokeh. Preserve face, expression, gaze and hair exactly; do not force closed eyes or a smile. Premium bridal editorial style, no text or extra people.',
      isPremium: true,
    ),
    PhotoTemplate(
      id: 'festival_portrait',
      imagePath: 'assets/templates/festival_portrait.webp',
      title: 'Festival Portrait',
      category: TemplateCategory.indian,
      description: 'Bright festive colors in a joyful portrait.',
      prompt:
          'Match the cover: joyful chest-up Holi portrait in a white kurta with vivid pink, yellow and orange festival colors in clothing and background, warm sunlight and photographic color. Keep face and hair free of added powder and unchanged. Preserve exact expression; no text or logos.',
    ),
    PhotoTemplate(
      id: 'instagram_trending',
      imagePath: 'assets/templates/instagram_trending.webp',
      title: 'Instagram Trending',
      category: TemplateCategory.social,
      description: 'A fresh creator portrait made for your feed.',
      prompt:
          'Match the cover: cozy casual creator portrait framed from head to waist, soft lilac knit sweater, lavender-lit bedroom/studio background and natural window light. Seated hand-on-cheek pose only if compatible with the original. Preserve face, expression and hair exactly; no beauty filter, text or UI.',
      isTrending: true,
    ),
    PhotoTemplate(
      id: 'travel_influencer',
      imagePath: 'assets/templates/travel_influencer.webp',
      title: 'Travel Influencer',
      category: TemplateCategory.travel,
      description: 'A vivid travel portrait in a beautiful destination.',
      prompt:
          'Match the cover: chest-to-waist travel selfie, practical olive jacket and backpack, vivid turquoise alpine lake and snow-capped mountains in crisp daylight. Keep believable wide-angle perspective and destination context. Preserve face, expression and hair exactly; no extra travelers or text.',
    ),
    PhotoTemplate(
      id: 'birthday_poster',
      imagePath: 'assets/templates/birthday_poster.webp',
      title: 'Birthday Poster',
      category: TemplateCategory.social,
      description: 'A celebratory portrait for your special day.',
      prompt:
          'Match the cover: intimate head-and-shoulders birthday portrait in elegant champagne-gold styling, softly glowing candles in the foreground and pastel pink balloons behind, with warm candlelit bokeh. Preserve face, expression, gaze and hair exactly; no numbers, writing or logos.',
    ),
    PhotoTemplate(
      id: 'couple_cinematic',
      imagePath: 'assets/templates/couple_cinematic.webp',
      title: 'Couple Cinematic',
      category: TemplateCategory.couple,
      description: 'A warm, cinematic celebration of connection.',
      prompt:
          'Match the cover: close affectionate waist-up couple portrait with both original people naturally close together, understated coordinated outfits, warm golden-hour backlight and softly blurred amber background. Preserve each person’s exact face, expression, gaze, hair and identity. Do not invent a partner, force a kiss/smile, merge faces or add text.',
      isPremium: true,
    ),
  ];
  static List<PhotoTemplate> get trending =>
      all.where((t) => t.isTrending).toList();
  static List<PhotoTemplate> get featured =>
      all.where((t) => t.isFeatured).toList();
}
