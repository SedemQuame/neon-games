# Design System: Glory Grid - Binance-Inspired

## 1. Visual Theme & Atmosphere
Glory Grid should feel like a compact trading product, not a promotional casino page. Use a near-black canvas, flat elevated cards, short labels, and one decisive accent color. The UI should prioritize fast scanning: balances, entry amounts, room status, and the next action.

## 2. Color Palette & Roles
- **Canvas Dark (#0B0E11):** Main app background.
- **Surface Card Dark (#1E2329):** Cards, sheets, bottom nav, secondary buttons.
- **Surface Elevated Dark (#2B3139):** Borders, dividers, selected dark rows.
- **Binance Yellow (#FCD535):** Primary CTA, selected filter, key numeric emphasis.
- **Binance Yellow Active (#F0B90B):** Pressed/active CTA edge.
- **Trading Up (#0ECB81):** Positive amounts and wins.
- **Trading Down (#F6465D):** Losses and errors.
- **Body Text (#EAECEF):** Primary text on dark surfaces.
- **Muted Text (#929AA5):** Captions, metadata, inactive labels.
- **On Yellow (#181A20):** Text on yellow buttons.

## 3. Typography Rules
Use Inter as the BinanceNova substitute. Use compact, direct headings and short body copy. Financial values should be bold, tabular-looking, and visually stronger than helper text. Avoid decorative letter spacing.

## 4. Component Stylings
* **Buttons:** Primary buttons are flat Binance Yellow with black text and 6-8px radius. Secondary buttons are dark cards with hairline borders.
* **Cards/Containers:** Flat dark blocks with 8-12px radius, 1px dark borders, and no glow-heavy shadows.
* **Inputs/Forms:** Dark filled inputs with subtle borders. Focus state uses yellow or info blue only as a thin edge.
* **Navigation:** Near-black bars with simple borders. Active tab uses yellow, not blue.
* **Badges:** Use small dark pills with yellow text. Reserve full yellow fills for selected states and primary actions.

## 5. Layout Principles
Mobile first. Use one-column lists on phones. Do not stack explanatory cards below obvious actions. Keep text short: one headline, one support line, then controls. Prefer labels like `Games`, `Rooms`, `Wallet`, `Entry`, `Payout`, and `Confirm` over full sentences.
