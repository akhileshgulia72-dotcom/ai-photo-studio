# Replaceable background image slots

Add optimized WebP photos using these exact filenames when ready:

- `home_hero.webp`
- `create_bg.webp`
- `premium_bg.webp`
- `enhancer_bg.webp`
- `profile_bg.webp`
- `result_bg.webp`

`PremiumBackground` loads these lazily on the screen that uses them. Until each
photo is supplied, it uses a remote photographic fallback and then a dark
surface if offline. The widget applies a dark readability overlay.
