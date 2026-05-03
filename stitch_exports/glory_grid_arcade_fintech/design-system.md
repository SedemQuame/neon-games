## Brand & Style

This design system establishes a **Premium Dark Arcade-Fintech** aesthetic. It targets a sophisticated audience that values the excitement of prediction gaming balanced with the security and precision of high-end financial tools. The personality is energetic yet disciplined, eliminating typical "casino clutter" in favor of structured data and high-velocity interaction.

The visual style is **Modern Corporate with Glassmorphic accents**. It utilizes deep, layered surfaces to create a sense of infinite depth, allowing image-led content to pop against a near-black canvas. Precision is communicated through razor-sharp typography and intentional use of vibrant accents, ensuring the user feels in control while experiencing the thrill of the game.

## Layout & Spacing

The layout follows a **Fluid Grid** model optimized for mobile-first responsiveness.
- **Grid:** A 4-column mobile grid expanding to 12 columns on desktop. 
- **Margins:** 16px side margins provide a safe area, while 12px gutters separate cards.
- **Rhythm:** A 4px baseline grid ensures vertical consistency.
- **Verticality:** Use a "sticky" architecture. The top bar remains fixed for balance management, while the bottom tab bar provides persistent navigation for core app sections.

## Elevation & Depth

Depth is achieved through **Tonal Layering** and **Subtle Inner Glows** rather than traditional drop shadows.
- **Surface Tiering:** Objects closer to the user (like active cards) use the lighter `surface_card` color.
- **Glow Effects:** Primary buttons and active indicators feature a soft 8px blur of the Electric Blue color to simulate a neon-lit arcade atmosphere.
- **Glassmorphism:** Navigation bars use a 20px backdrop blur with a 10% white tint to maintain context of the content scrolling beneath them.
- **Overlays:** Text on image-led cards must sit on a 40% black gradient overlay to ensure WCAG AA readability.

## Components

- **Buttons:** 
  - *Primary:* Electric Blue background, white bold text, slight inner glow.
  - *Secondary:* Transparent with a 1px Blue Black border.
  - *Action:* Large, full-width "Place Bet" buttons with haptic-ready visual weight.
- **Image-led Cards:** Aspect ratio 16:9 or 4:5. Features a 12px radius, a bottom-weighted gradient overlay, and high-contrast white typography for titles.
- **Chips/Badges:** Small, pill-shaped indicators for "Live," "Hot," or "New." Use secondary accent (Gold) for VIP levels.
- **Inputs:** Deep Slate background with 1px Blue Black border. On focus, the border transitions to Electric Blue.
- **Bottom Tab Bar:** 64px height, blurred background, with icons that transition from Slate to Electric Blue when active.
- **Balance Header:** A prominent "Fintech-style" sticky bar showing currency in Gold and a prominent "Deposit" button in Success Green.