# Handoff: Softfill website — Home page

## Overview
The marketing page for Softfill at https://softfill.nutrx-labs.com. This package covers the **Home** page only. Support, Privacy, Terms and 404 are not designed yet; build them from the same system (see "Not designed yet").

## About the design files
`design/Website Home.dc.html` is a **design reference built in HTML**, not production code. Rebuild it as static HTML + CSS per the site's standing instructions (no frameworks, no CDNs, no third-party requests). Open it in a browser to see it live. URL params: `?theme=light|dark`, `?lang=en|de|ro|ru`, `?menu=1` (language menu open), `?still=1` (freeze the hero animation).
`design/Website Boards.dc.html` shows every review frame: 1440 and 390 wide, light and dark, the German hero, and the language menu open.

**Fidelity: high.** Match the colors, type, spacing, radii and copy.

## Copy rules (must follow; also in copy-rules.md)
- Never mention ads anywhere on the site, in any language: no "no ads", "ad-free", "fewer ads", "no ads for kids".
- The same goes for "no tracking", "no analytics" and "collects no data" as selling points.
- Exception: the Privacy page states current data practices as plain facts in body text, with a "last updated" date. Never as a badge, chip or highlight.
- Sell what stays true: the grown-up check every time, the Little level, no accounts, calm by design.
- No exact prices, and nothing about Studio until v1.1 ships.

## Page structure (top to bottom)
Content max width 1200 (hero 1280). Side padding `clamp(20px, 4vw, 40px)`. Section padding `clamp(56px, 8vw, 112px)`. Sections alternate between `bg` and `surface` grounds, with hairline `line` separators.

1. **Header** (sticky, 68 tall, translucent `bg` + blur, 1px `line` bottom): mark + "Softfill" (21/800) · language button (pill, `surface-2`, globe + "EN" + chevron) · App Store badge, or a "Coming soon to the App Store" pill (shortens to "Coming soon" below 560px).
   - **Language menu**: popover 208 wide, radius 20, sheet shadow. Rows 44 tall: name, code and a check on the current one; the current row is `surface-2`. Real links to `/`, `/de/`, `/ro/`, `/ru/` that keep the visitor on the same page. Closes on Escape and on an outside click.
2. **Hero**: two columns that wrap on narrow screens.
   - Left: 60px icon + "Softfill" + tagline "Coloring for iPad". H1 "Calm coloring, one tap at a time." (`clamp(44px, 5.6vw, 80px)`/800, −0.035em, lh 1). Lede, then the CTA row: App Store badge or the "Coming soon" pill (56 tall), plus the note "Free packs to start · No account needed".
   - Right: an iPad frame (radius ~40, bezel #0E0F11) showing the Canvas: top bar with progress and a Fill/Draw switch, tool rail, the drawing mid-fill, palette dock.
   - The mock animates tap-to-fill ripples on the drawing; for production use a short muted looping video (or an animated WebP) rendered from the app, with a still poster frame for `prefers-reduced-motion`.
3. **How it works** (`surface`): H2 "Tap. Draw. Watch it come together." Three cards (radius 28, `bg`, inner art 3:2 radius 20): **Tap to fill** · **Draw if you like** (with a green "Inside lines" chip) · **Watch the time-lapse** (play button + scrubber "0:00 / 0:06"). Grid `auto-fit, minmax(260px, 1fr)`.
4. **Four levels**: H2 "Four levels, from little hands to steady ones." Four cards, each on its level's tint, with art, a dot and the name in the deep color, and the app's exact copy:
   - Little artists — "Big shapes, bright colors · ages 3+"
   - Easy — "Relaxed scenes · 10–15 min each"
   - Detailed — "More regions, finer lines · 20–40 min"
   - Intricate — "Mandalas & patterns · an hour or more"
   Art: Easy uses Sunny Meadow (colored); the other three need colored renders from the app.
5. **For parents**: one rounded panel (`surface-2`, radius 40), with a "For parents" chip in the Little tint. H2 "A grown-up stays in charge." Lede: "Softfill is rated 4+. Children can color on their own, while anything that costs money or leaves the app waits for you." Four points (40px icon tile + title + text):
   - **A grown-up check, every time**: "Purchases, settings and links out of the app ask a grown-up first, every time."
   - **Made for little artists**: "Big shapes and bright colors for ages 3+. No prices, and nothing to tap away to."
   - **No accounts**: "Nothing to sign up for. Your art stays on your device and in your own iCloud." (Until iCloud ships: "…stays on your device, and soon in your own iCloud too.")
   - **Calm by design**: "No countdowns, no scores. Color at your own pace."
   Right of the points: a static mock of the parental gate (the "Grown-ups only" card with keypad).
6. **Pricing**: H2 "Free to start. Unlock what you love." Three cards: **Free packs** (Easy tint icon) · **Packs to keep** (Detailed tint icon) · **Softfill Unlimited** (an `ink` card with a "7 days free" green tag, mentions Family Sharing). Fine print: "The App Store shows the exact prices for your country…"
7. **iPad and iPhone** (`surface`): until iPhone ships, "Made for iPad. Coming to iPhone." with an iPhone frame overlapping an iPad and a "Coming soon" pill on the phone. After it ships: "On iPad and iPhone, always in sync."
8. **Closing CTA**: 96px icon, H2 "Your first drawing is waiting.", "Free packs to start. No account needed.", badge or pill.
9. **Footer**: mark + "© 2026 nutrx labs" · Privacy · Terms · Support · softfill@nutrx-labs.com.

## Design tokens
| Token | Light | Dark |
|---|---|---|
| bg | #FBFAF7 | #101215 |
| surface | #FFFFFF | #191C20 |
| surface-2 | #F5F3F0 | #24272B |
| line | #E3E1DD | #32363B |
| ink | #1C1F25 | #F3F2EF |
| ink-2 | #5A5E65 | #B0AEA8 |
| stage (device screen bg) | #F0EEEA | #0B0D10 |

Level accents (fill · tint · deep), light:
- Little: #DF9B44 · #FFEBD2 · #7E4600
- Easy: #69C27E · #DCF7E1 · #0B5D2A
- Detailed: #47B7F1 · #D6F4FF · #005D8D
- Intricate: #BE95EC · #F5E8FF · #663E8E

Dark accents: fill `oklch(0.78 0.13 h)`, tint `oklch(0.3 0.05 h)`, deep `oklch(0.85 0.09 h)`, with h = 70 / 150 / 235 / 305. In dark mode the Unlimited card inverts (light card, dark text). Drawing paper is always white. Focus ring: 3px #47B7F1, 3px offset.

Type: `ui-rounded, "SF Pro Rounded", "Nunito"` (self-host Nunito; the mock loads it from Google Fonts, which production must not do). H2 `clamp(34px, 4.2vw, 56px)`/800, −0.03em. Card titles 22/800. Body 16–19, lh 1.5–1.55, `ink-2`. `text-wrap: balance` on headings, `pretty` on body.
Radii: chip 10 · button 14 · card 20 · large card 28 · panel 40 · pill 999.

Icons: the mock uses Material Symbols from Google Fonts. Replace them with inline SVGs (lock, child_care, no_accounts, spa, palette, collections_bookmark, all_inclusive, schedule, language, expand_more, play_arrow, family_restroom).

## Translations
Only the hero and header strings are drafted in DE, RO and RU (they live in `STR` and the `isDe`/`isRo`/`isRu` blocks of the design file). These are drafts; get them read by native speakers and align them with the app's `Localizable.xcstrings`. German is the longest language; the hero H1 uses `hyphens: auto`.

## Assets
- `assets/meadow-lineart.png`: the Sunny Meadow line art used in every mock. For production, render colored versions from the app (hero mid-fill, Easy card, time-lapse poster, device mocks) as WebP/AVIF with PNG fallbacks.
- Brand: `design/brand/icon/AppIcon-light-1024.png` (header 34px, hero 60px, closing CTA 96px, footer 28px, favicon) and `design/brand/wordmark/softfill-wordmark-ink.svg` / `-light.svg` (dark mode) in the header (22px tall) and hero (26px tall).
- Still needed: Apple's official localized App Store badges, colored art for the Little, Detailed and Intricate cards, and an OG image.

## Not designed yet
Support (FAQ using `<details>`, with one answer expanded), Privacy and Terms (one long-form article template), and 404. Reuse the header and footer, the tokens, and the readable column width (~680).

## Files
```
README.md                      this file
copy-rules.md                  copy rules (merge into the web repo's CLAUDE.md)
design/Website Home.dc.html    the page (open in a browser)
design/Website Boards.dc.html  review frames
design/support.js, image-slot.js   runtime for the mocks only
design/assets/meadow-lineart.png
assets/meadow-lineart.png
```
