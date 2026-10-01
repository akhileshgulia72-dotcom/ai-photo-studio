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
        'distorted face, extra fingers, plastic skin, altered identity, blurry, watermark, text',
    this.isPremium = false,
    this.creditsRequired = 1,
    this.aspectRatio = '4:5',
    this.isTrending = false,
    this.isFeatured = false,
  });
  final String id, title, description, prompt, imagePath, negativePrompt, aspectRatio;
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
      imagePath: 'assets/templates/luxury_black_suit.jpg',
      title: 'Luxury Black Suit',
      category: TemplateCategory.luxury,
      description:
          'A refined, cinematic fashion portrait with timeless confidence.',
      prompt:
          'Transform the person in the reference image into a sophisticated luxury fashion portrait wearing a perfectly tailored black suit. Preserve identity, facial structure, hairstyle and recognizable characteristics. Premium dark studio, elegant cinematic rim lighting, realistic skin texture, natural proportions, detailed fabric, editorial photography.',
      isFeatured: true,
      isTrending: true,
    ),
    PhotoTemplate(
      id: 'ceo_portrait',
      imagePath: 'assets/templates/ceo_portrait.jpg',
      title: 'CEO Portrait',
      category: TemplateCategory.luxury,
      description:
          'A polished executive portrait with a premium editorial finish.',
      prompt:
          'Create a premium executive portrait of the same person in refined business attire. Preserve identity and face exactly; realistic skin, natural proportions, confident expression, soft studio lighting, tasteful luxury office background, professional editorial photography.',
    ),
    PhotoTemplate(
      id: 'luxury_car',
      imagePath: 'assets/templates/luxury_car.jpg',
      title: 'Luxury Car',
      category: TemplateCategory.luxury,
      description: 'Step into a dramatic automotive campaign.',
      prompt:
          'Place the same person beside a beautiful luxury performance car at golden hour. Preserve identity and facial features. Realistic automotive campaign photography, elegant reflections, natural pose, cinematic light, refined styling.',
    ),
    PhotoTemplate(
      id: 'night_city_luxury',
      imagePath: 'assets/templates/night_city_luxury.jpg',
      title: 'Night City Luxury',
      category: TemplateCategory.luxury,
      description: 'A sophisticated night portrait among city lights.',
      prompt:
          'Create a luxury night-city fashion portrait of the same person. Preserve identity and facial structure. Tailored modern outfit, softly glowing city lights, realistic reflections, cinematic depth, natural skin and proportions.',
    ),
    PhotoTemplate(
      id: 'cinematic_poster',
      imagePath: 'assets/templates/cinematic_poster.jpg',
      title: 'Cinematic Movie Poster',
      category: TemplateCategory.cinematic,
      description: 'A dramatic hero frame with cinematic color and light.',
      prompt:
          'Transform the same person into the lead of a dramatic cinematic movie poster scene. Preserve identity, face, hairstyle and proportions. Rich atmospheric lighting, detailed wardrobe, striking composition, realistic skin, high-end film still.',
    ),
    PhotoTemplate(
      id: 'dark_action_hero',
      imagePath: 'assets/templates/dark_action_hero.jpg',
      title: 'Dark Action Hero',
      category: TemplateCategory.cinematic,
      description: 'A bold action portrait with moody atmosphere.',
      prompt:
          'Create a tasteful dark action-hero portrait featuring the same person. Preserve identity and facial structure. Dramatic directional light, subtle atmospheric haze, realistic clothing and skin texture, cinematic composition.',
    ),
    PhotoTemplate(
      id: 'hollywood_portrait',
      imagePath: 'assets/templates/hollywood_portrait.jpg',
      title: 'Hollywood Portrait',
      category: TemplateCategory.cinematic,
      description: 'Red-carpet polish with a timeless film-star look.',
      prompt:
          'Create a classic Hollywood editorial portrait of the same person. Preserve identity and natural facial details. Elegant styling, warm cinematic key light, subtle film grain, realistic skin, flattering but natural proportions.',
    ),
    PhotoTemplate(
      id: 'crime_thriller',
      imagePath: 'assets/templates/crime_thriller.jpg',
      title: 'Crime Thriller',
      category: TemplateCategory.cinematic,
      description: 'An atmospheric neo-noir character portrait.',
      prompt:
          'Create a neo-noir crime-thriller portrait of the same person. Preserve identity, facial structure and hairstyle. Rain-lit city atmosphere, restrained shadows, realistic skin texture, cinematic framing, no weapons or graphic content.',
    ),
    PhotoTemplate(
      id: 'linkedin_professional',
      imagePath: 'assets/templates/linkedin_professional.jpg',
      title: 'LinkedIn Professional',
      category: TemplateCategory.professional,
      description: 'A welcoming, polished profile photo for work.',
      prompt:
          'Create a natural professional headshot of the same person in smart business-casual clothing. Preserve identity and facial structure. Clean softly lit neutral background, warm approachable expression, realistic skin, accurate proportions, crisp professional photography.',
    ),
    PhotoTemplate(
      id: 'corporate_ceo',
      imagePath: 'assets/templates/corporate_ceo.jpg',
      title: 'Corporate CEO',
      category: TemplateCategory.professional,
      description: 'Confident leadership portrait for a company profile.',
      prompt:
          'Create a confident corporate leadership portrait of the same person. Preserve identity and face. Tailored business attire, modern office softly out of focus, balanced professional lighting, realistic skin and natural posture.',
    ),
    PhotoTemplate(
      id: 'startup_founder',
      imagePath: 'assets/templates/startup_founder.jpg',
      title: 'Startup Founder',
      category: TemplateCategory.professional,
      description: 'Modern founder energy in a creative workspace.',
      prompt:
          'Create a modern startup-founder portrait of the same person in a bright contemporary workspace. Preserve identity and facial structure. Smart casual clothing, candid confident pose, natural window light, realistic skin and proportions.',
    ),
    PhotoTemplate(
      id: 'business_magazine',
      imagePath: 'assets/templates/business_magazine.jpg',
      title: 'Business Magazine',
      category: TemplateCategory.professional,
      description: 'An editorial cover-style business portrait.',
      prompt:
          'Create a premium business-magazine editorial portrait of the same person. Preserve identity, hairstyle and facial structure. Refined wardrobe, sculpted studio lighting, tasteful modern background, realistic skin, sharp photography.',
    ),
    PhotoTemplate(
      id: 'royal_indian',
      imagePath: 'assets/templates/royal_indian.jpg',
      title: 'Royal Indian',
      category: TemplateCategory.indian,
      description: 'Regal Indian-inspired styling with rich details.',
      prompt:
          'Create an elegant royal Indian portrait of the same person in tasteful traditional attire with refined embroidery. Preserve identity and facial structure. Warm palace-inspired setting, rich jewel tones, realistic textiles, natural skin and dignified lighting.',
      isPremium: true,
    ),
    PhotoTemplate(
      id: 'traditional_kurta',
      imagePath: 'assets/templates/traditional_kurta.jpg',
      title: 'Traditional Kurta',
      category: TemplateCategory.indian,
      description: 'A graceful traditional look for a festive occasion.',
      prompt:
          'Dress the same person in a tasteful, beautifully fitted traditional kurta. Preserve identity and facial structure. Soft festive Indian setting, natural warm light, realistic fabric and skin, relaxed confident pose.',
    ),
    PhotoTemplate(
      id: 'wedding_look',
      imagePath: 'assets/templates/wedding_look.jpg',
      title: 'Wedding Look',
      category: TemplateCategory.indian,
      description: 'A celebration-ready portrait with elegant styling.',
      prompt:
          'Create a refined Indian wedding portrait of the same person in elegant celebration attire. Preserve identity, face and hairstyle. Warm decorative lights, graceful setting, detailed realistic fabric, natural skin and proportions.',
      isPremium: true,
    ),
    PhotoTemplate(
      id: 'festival_portrait',
      imagePath: 'assets/templates/festival_portrait.jpg',
      title: 'Festival Portrait',
      category: TemplateCategory.indian,
      description: 'Bright festive colors in a joyful portrait.',
      prompt:
          'Create a joyful Indian festival portrait of the same person in tasteful colorful traditional clothing. Preserve identity and facial features. Soft festive lights and decorations, natural skin texture, vibrant but realistic color.',
    ),
    PhotoTemplate(
      id: 'instagram_trending',
      imagePath: 'assets/templates/instagram_trending.jpg',
      title: 'Instagram Trending',
      category: TemplateCategory.social,
      description: 'A fresh creator portrait made for your feed.',
      prompt:
          'Create a contemporary social-media creator portrait of the same person. Preserve identity, facial structure and hairstyle. Trend-forward tasteful styling, clean vibrant background, flattering natural light, realistic skin and polished composition.',
      isTrending: true,
    ),
    PhotoTemplate(
      id: 'travel_influencer',
      imagePath: 'assets/templates/travel_influencer.jpg',
      title: 'Travel Influencer',
      category: TemplateCategory.travel,
      description: 'A vivid travel portrait in a beautiful destination.',
      prompt:
          'Place the same person in a beautiful travel destination scene with tasteful contemporary travel styling. Preserve identity and face. Natural daylight, realistic environment, editorial travel photography, natural skin and proportions.',
    ),
    PhotoTemplate(
      id: 'birthday_poster',
      imagePath: 'assets/templates/birthday_poster.jpg',
      title: 'Birthday Poster',
      category: TemplateCategory.social,
      description: 'A celebratory portrait for your special day.',
      prompt:
          'Create a cheerful birthday portrait of the same person with elegant balloons and soft celebratory details. Preserve identity and facial structure. Rich but tasteful colors, studio-quality light, realistic skin, crisp portrait composition.',
    ),
    PhotoTemplate(
      id: 'couple_cinematic',
      imagePath: 'assets/templates/couple_cinematic.jpg',
      title: 'Couple Cinematic',
      category: TemplateCategory.couple,
      description: 'A warm, cinematic celebration of connection.',
      prompt:
          'Create a warm cinematic couple portrait using the people in the reference image, keeping each person recognizable and preserving facial structure. Natural affectionate pose, soft golden-hour light, realistic skin and proportions, tasteful editorial photography.',
      isPremium: true,
    ),
  ];
  static List<PhotoTemplate> get trending =>
      all.where((t) => t.isTrending).toList();
  static List<PhotoTemplate> get featured =>
      all.where((t) => t.isFeatured).toList();
}
