# Softfill web — standing instructions

This repo is the website for **Softfill**, a native iOS coloring app (iPad first, iPhone supported) by
nutrx labs. The site is the app's public face and also hosts the pages the app and App Store Connect link
to. It lives at **https://softfill.nutrx-labs.com**.

## Repo map

```
CLAUDE.md                      these standing instructions
build.py                       the build: templates + strings → docs/ (Python 3 standard library only)
src/templates/                 page templates and shared partials (see "Build")
src/strings/                   one JSON file of UI strings per language: en, de, ro, ru
src/articles/                  long-form bodies per language: privacy.en.html, terms.de.html, …
src/assets/                    css/, fonts/ (self-hosted Nunito with its OFL licence), img/, video/, js/
tools/                         helpers that write into src/: art/ (Home's art from the app's drawings),
                               make_og.py (Open Graph images), screenshots.sh
docs/                          the generated site that GitHub Pages serves; never edited by hand
design_handoff_softfill_web/   the website design from Claude Design (read-only; regenerate from Claude
                               Design, don't hand-edit). README.md is the build spec for Home; copy-rules.md
                               is merged below; design/*.dc.html are references to open in a browser, never
                               code to copy (their support.js and image-slot.js runtimes, Google Fonts and
                               Material Symbols must not reach the site).
```

The app itself is a separate repo, checked out next to this one at `../softfill`
(github.com/a7ex-turcan/softfill). It is the source of truth for every product fact on this site. Read it,
never edit it from here. Start sessions with `claude --add-dir ../softfill` so its files are readable.

## Why the site exists, and its deadline

App Store Connect needs a **privacy policy URL** and a **support URL** for every language, and an external
TestFlight build needs the privacy URL too. So the privacy and support pages must be live before the app's
first external TestFlight build, which is the end of the app's Phase 3 (see `../softfill/PLAN.md`,
"Website track"). Everything else on the site can follow.

## Pages and URLs

English is the default at the root; German, Romanian and Russian live under a language folder with the same
page names. These URLs are final, because the app and App Store Connect will point at them.

| Page | English | Other languages | What it is |
|---|---|---|---|
| Home | `/` | `/de/`, `/ro/`, `/ru/` | The marketing page |
| Privacy | `/privacy` | `/de/privacy`, … | Privacy policy (linked from the app and App Store Connect) |
| Terms | `/terms` | `/de/terms`, … | Terms of use (linked from the app's unlock sheet) |
| Support | `/support` | `/de/support`, … | FAQ and contact (App Store Connect support URL) |
| Not found | `404.html` | — | Friendly 404 with a way home |

Serve each page as `privacy/index.html` and so on, so the URLs need no `.html`. GitHub Pages then answers
`/privacy` with a 301 to `/privacy/`, so both forms work and the app and App Store Connect can use either;
the site's own links, canonical URLs, `hreflang` and the sitemap use the trailing slash to skip the redirect.
Every page carries `hreflang` links to its other languages and a language switcher that keeps the visitor on
the same page.

### Home, top to bottom
Designed and approved: `design_handoff_softfill_web/README.md` is the spec (structure, sizes, copy,
tokens, states) and wins over this summary.

1. **Hero**: the name, a one-line pitch, the App Store badge, an iPad showing a drawing mid-fill.
2. **How it works**: tap to fill, draw if you like, watch the time-lapse of your finished piece.
3. **Four levels**, each in its accent color, with the app's own copy (see Product facts).
4. **For parents**: a grown-up stays in charge (the parental gate), the Little level, no accounts, art kept
   private on the device and in the user's own iCloud.
5. **How pricing works**: free packs to start, packs to unlock, Unlimited with a 7-day free trial. No exact
   prices on the site; they differ by country and the App Store shows the real ones.
6. **iPad and iPhone**, art kept in sync through the user's own iCloud.
7. A closing call to action.

Built 2026-10-12, with these choices on top of the handoff:
- The hero's drawing is a video (Sunny Meadow in the "Garden party" palette, eleven fills), with the HTML
  canvas chrome around it so the device's text can be translated. 1152 px for wide screens, 768 px below
  700 px; no video at all under reduced motion.
- Art from the app's own drawings: the Little card is Sea Turtle (Coral reef), the Easy card Fox Den (Fox
  glade), the Detailed card Kingfisher Stream (Pine hollow), the Intricate card Moon Mandala (Cosmos), the
  time-lapse Pond Ducks (Beach day). The Detailed and Intricate cards replaced "First packs on the way" on
  2026-10-13, when those levels got their packs.
- "No accounts" says "on your device and in your own iCloud", because iCloud sync is built (Product facts,
  Devices). The Devices section uses the shipped copy since 2026-10-13 (`IPHONE_SHIPPED`, which also hides the
  phone's "Coming soon" pill), and the hero's tagline and the Home title name both devices.

### Support
A short intro, an FAQ with expandable answers (use `<details>`), and the contact address. FAQ topics:
restore purchases, cancel or change a subscription, iCloud sync, Family Sharing, the parental gate, where
finished art goes.

### Privacy and Terms
One long-form article template for both: headings, readable line length, a "last updated" date, good on a
phone. Terms point to Apple's standard EULA and add only what it does not cover.

### Shared on every page
- **Header**: the Softfill mark, the language switcher (EN · DE · RO · RU), the App Store badge.
- **Footer**: Privacy · Terms · Support, `softfill@nutrx-labs.com`, "© nutrx labs".

## Product facts

Check these against `../softfill` before publishing; the app wins if they disagree.

- **What it is**: a calm coloring app. Tap an area to fill it with a ripple, or draw with a brush that can
  stay inside the lines. Every drawing comes with hand-picked palettes, and any color is one tap away.
  Finished pieces go to a Gallery with a time-lapse replay. Line art is always drawn on top.
- **Levels**, with the app's exact copy:
  - Little artists — "Big shapes, bright colors · ages 3+"
  - Easy — "Relaxed scenes · 10–15 min each"
  - Detailed — "More regions, finer lines · 20–40 min"
  - Intricate — "Mandalas & patterns · an hour or more"
  - Studio (freehand pencil, marker, watercolor) is **v1.1**. Do not promise it on the site until it ships,
    even though the app's Unlimited copy mentions it.
- **Content today** (checked 2026-10-13, the launch catalog): every level has its free packs and two paid
  packs. Little: Sunny Days, Under the Sea, Farm Friends (free), Dino Park, Unicorn Valley (paid). Easy: Meadow
  Friends, Into the Woods (free), Seaside Towns, Pets at Home (paid). Detailed: Botanical Studies, Garden Birds
  (free), Japanese Gardens, City Windows (paid). Intricate: Mandala Nights, Geometric Calm (free), Art Nouveau,
  Stained Glass (paid). The rule: Little has 3 free packs, Easy, Detailed and Intricate 2 each, and every paid
  pack has one drawing that is free to try. Pack sizes and the reasoning: `../softfill/PLAN.md`, Content track.
  Never give a number of packs; "free packs in every level" is true now. Current list:
  `../softfill/Packages/SoftfillKit/Sources/Content/Resources/catalog.json`.
- **Pricing (internal reference only)**: packs $1.99 each, yours forever; Softfill Unlimited $2.99 a month
  or $19.99 a year with a 7-day free trial, every pack included, new packs monthly. Unlimited is shared
  through Family Sharing; packs are not.
- **Kids and parents**: rated 4+ in a general category, **not** Apple's Kids Category. A parental gate (type
  a three-digit number written in words) is asked every time before any purchase, Settings, Restore or link
  that leaves the app. The Little level shows no prices, no Unlimited banner, no share buttons and no
  external links; locked content says "Ask a grown-up".
- **No** ads, accounts, analytics or tracking in v1, and no backend. Rewarded ads are a possible
  post-release experiment outside the kids levels (`../softfill/PLAN.md`, Phase 5).
- **Copy rules** (merged from `design_handoff_softfill_web/copy-rules.md`):
  - Never mention ads on the site, in any language: no "no ads", "ad-free", "fewer ads", "no ads for kids".
  - The same for "no tracking", "no analytics" and "collects no data" as selling points: not in headlines,
    feature lists, badges, page titles, meta descriptions or social images.
  - Exception: the Privacy page states current data practices plainly as facts in body text (for example
    "The app does not collect personal data, show ads or use analytics"), with its "last updated" date.
    Never as a badge, chip or highlight. It changes when the practices do.
  - Sell what stays true: the grown-up check every time, the Little level (no prices, nothing to tap away
    to), no accounts (device and the user's own iCloud), calm by design (no countdowns, no scores).
  - No exact prices, and nothing about Studio until v1.1 ships.
- **Free drawing of the day**: built in the app on 2026-10-11 (Phase 3 item 5), so it is in the first
  TestFlight build and Support, Terms and Privacy describe it. One drawing from a paid pack opens free until
  local midnight, then locks again. Finished, it stays in the Gallery; unfinished, its colors are kept until
  the pack is unlocked. An opt-in local reminder at 9:00 names the day's drawing. Hidden for Unlimited members.
- **Devices**: iPad first, iPhone supported. iCloud sync is built (Phase 3 item 6, 2026-10-12, waiting on its
  two-device check), so the pages describe it as part of the app. The iPhone layouts are built (Phase 3 item 7,
  2026-10-12): v1 runs on both, and on iPhone in portrait only.
- **Languages**: English, German, Romanian, Russian.
- **App Store**: app id `6820982967`, so the link will be `https://apps.apple.com/app/id6820982967`. Until
  the app is live, say "Coming soon to the App Store" instead of showing a badge that links nowhere. Once it
  is live, add the Smart App Banner meta tag (`apple-itunes-app`).

## Privacy facts for the privacy page

- App Privacy label: **Data Not Collected**. No accounts, no analytics, no ads, no tracking, no third-party
  SDKs. If crash reporting is ever added it is Apple's built-in reports only.
- Artwork and progress are stored on the device. With iCloud sync on (a Settings toggle), they sync through
  the user's own iCloud private database; nutrx labs cannot see it. With it off, art stays on the device.
- Purchases and subscriptions are handled by Apple through StoreKit; the app never sees payment details.
- The audience is parents and adult colorists; children use the app behind the parental gate.
- Contact for privacy questions: `softfill@nutrx-labs.com`.
- The website itself sets no cookies and makes no third-party requests; say so.
- **Open**: the legal entity name and address to name as the publisher. Ask Alex.

## Design

Polished, to the same standard as the app. The look is drafted in **Claude Design** first and approved by
Alex before anything is built. The app's design lives in the Claude Design project "Softfill app"
(id `7cf2956a-3c35-42b5-96df-3aa3373ec323`); the site's design is its own project that reuses that design
system. Ask for each page at 390 and 1440 wide, light and dark, the Home hero in German as well (the
longest language), plus two states: the language switcher open and an FAQ answer expanded.

Design system, from `../softfill/design_handoff_softfill/spec/design-tokens.md` (read it in full):

- **Neutrals** (light / dark): bg #FBFAF7 / #101215 · surface #FFFFFF / #191C20 · surface-2 #F5F3F0 /
  #24272B · line #E3E1DD / #32363B · ink #1C1F25 / #F3F2EF · ink-2 #5A5E65 / #B0AEA8. Text is ink or ink-2
  only; ink-3 is never text.
- **Level accents** (fill · tint · deep, light): Little #DF9B44 · #FFEBD2 · #7E4600; Easy #69C27E · #DCF7E1 ·
  #0B5D2A; Detailed #47B7F1 · #D6F4FF · #005D8D; Intricate #BE95EC · #F5E8FF · #663E8E. Dark values are in
  the tokens file. Accents say "which level"; they never color a call to action.
- **Calls to action** are ink buttons (dark button, light label), like the app's purchase buttons.
- **Type**: the app uses SF Pro Rounded. On the web use the `ui-rounded` system face first, then a
  self-hosted rounded fallback (Nunito, OFL, which the mocks used as a stand-in). Heavy weights for
  headings with slight negative tracking.
- **Radii**: chip 10 · button 14 · card 20 · sheet 28 · pill 999. **Spacing**: 4-pt grid (4 · 8 · 12 · 16 ·
  24 · 32 · 48). Drawing paper is always white, in dark mode too.
- **Motion**: gentle; honour `prefers-reduced-motion`.

Assets:

- **Line art**: `../softfill/Packages/SoftfillKit/Sources/Content/Resources/Drawings/<id>/lineart.png`
  (black on white, 4-bit grey, 1536 wide for Little and Easy, 3520 for Detailed and Intricate), with
  `regions.bin` and `drawing.json` beside it.
- **Colored art and videos**: `tools/art/build.sh` renders them from those files, as the app colors them: each
  region in its palette color by slot, the line art multiplied on top. Slots count through the app's swatches
  (`Palette.swatch(forSlot:)`): the main colors, or for palettes with second tones (Detailed and Intricate)
  each main color followed by its second. `tools/art/recipe.json` lists every
  output (drawing, palette, which regions, crop, sizes); `render --debug <id> out.png` numbers a drawing's
  regions for writing a recipe. Stills come out as AVIF with a JPEG fallback, videos as H.264 MP4, all with
  the macOS frameworks only. Rerun it when the app's art or palettes change, then rebuild. Two things in
  `home.html` and the strings follow the `hero-poster` output by hand: the hero's progress line ("44 of 55
  colored": counted regions filled in its first frame, out of all counted regions) and the six dock swatches
  (its palette's colors), in both device mocks. Change them together.
- **Screenshots**: from the app on the iPad simulator now; iPhone ones after the Phase 3 layouts.
- **App Store badges**: Apple's official, localized badges from Apple's marketing resources, self-hosted,
  used as Apple's guidelines say.
- **Brand** (designed 2026-10-10): the app icon and the wordmark are in `src/assets/img/brand/`, copied from
  `../softfill/design_handoff_softfill/brand/`; the rules are in `../softfill/design_handoff_softfill/spec/brand.md`
  (read it in full). Icon: `AppIcon-light` / `-dark` as SVG and 1024 PNG. Wordmark: `softfill-wordmark-ink`
  (light backgrounds), `-light` (dark backgrounds), `-ink-mono` (one color), as SVG plus 2x and 4x PNGs. Sizes
  on the site come from `design_handoff_softfill_web/README.md` (icon 34 px in the header, 60 px in the hero,
  96 px at the closing CTA, 28 px in the footer; wordmark 22 px tall in the header and 26 px in the hero), which
  wins over brand.md's general 24 px header note. Keep the wordmark at least 18 px tall with clear space the
  height of its "o" on every side. The favicon, the Apple touch icon and the Open Graph image are made from the
  icon. The handoff's `design/brand/` holds the same files for its mocks; the site serves the copies in
  `src/assets/img/brand/`. If the designer changes them, copy them again; never redraw.

## Build

Decided 2026-10-09: plain HTML and CSS, generated by one small script. No React or other framework, no
npm, no static-site generator, no CDNs. The site is five pages in four languages; a framework would add a
dependency tree, a slower first paint and GitHub Pages routing work for no gain.

- **Templates** (`src/templates/`): `base.html` holds `<head>`, the header with the language menu and the
  footer; `home.html`, `support.html`, `article.html` (Privacy and Terms) and `404.html` fill its main
  slot. Placeholders are `{{ key }}` for strings and `{{> partial }}` for partials; nothing more clever.
- **Strings** (`src/strings/<lang>.json`): every visible string, page title and meta description, keyed
  the same in all four files. Values are escaped as text; a key ending in `_html` is inserted as HTML
  (links, emphasis) and is the only way markup gets in.
- **Articles** (`src/articles/<page>.<lang>.html`): the Privacy and Terms bodies as plain HTML fragments,
  with their "last updated" date.
- **Languages are published one at a time**: a language is built, listed in the switcher, in `hreflang` and in
  the sitemap once `src/strings/<lang>.json` exists. Until a second language exists, the switcher and the
  `hreflang` links are left out (an English page under `/de/` marked `lang="de"` would mislead browsers and
  search engines alike).
- **Product state** lives in two flags at the top of `build.py`: `APP_LIVE` (App Store badge and Smart App
  Banner instead of "Coming soon") and `IPHONE_SHIPPED` (the Devices copy on Home). Flip them in the change that
  updates the matching product fact here.
- **`build.py`**: runs on the macOS system Python (3.9) with the standard library only. For every page and
  language it writes `docs/<lang-prefix><page>/index.html` (English at the root, `docs/de/…` and so on),
  plus `docs/404.html`, `docs/CNAME`, `docs/robots.txt` and `docs/sitemap.xml`, and copies `src/assets/`
  to `docs/assets/`. It fills in each page's `lang`, canonical URL, `hreflang` links and the language
  menu's links to the same page in the other languages, and appends a short content hash to the CSS and JS
  URLs so browsers pick up changes.
  - A key missing from any language fails the build and names it. While translations are drafts,
    `python3 build.py --allow-missing` falls back to English and lists every gap.
  - `python3 build.py --check` rebuilds into a temporary folder and fails if `docs/` differs, so a commit
    never ships stale output.
  - Every build also checks that each root-relative link and asset in the output exists.
- **Open Graph images** (`src/assets/img/og/softfill-og-<lang>.png`, 1200 × 630) come from the hero strings and
  the brand files: `tools/art/build.sh og-art && python3 tools/make_og.py` after the hero copy changes (the
  art render is an intermediate file in the git-ignored `tools/art/out/`). The favicon set
  (`src/assets/img/icon/`) is the light app icon: the SVG with iOS-style rounded corners, a 32 px PNG and the
  180 px Apple touch icon.
- **Preview**: `python3 build.py && python3 -m http.server 8000 -d docs`, then http://localhost:8000.
  Absolute links like `/privacy` need the local server; `file://` will not resolve them.
- Change `src/` and rebuild; never edit `docs/` by hand. Commit `src/` and the rebuilt `docs/` together.
- JavaScript only where HTML cannot do it, in one small self-hosted file: the language menu (a `<details>`)
  closing on Escape, an outside click and focus leaving; starting the hero video when autoplay alone didn't;
  the hero's pause button (WCAG 2.2.2: the loop runs longer than five seconds); and the time-lapse card's
  play button and scrubber. The FAQ uses `<details>`. The hero is a muted looping
  video over a poster image; its `<source>`s match only `prefers-reduced-motion: no-preference`, so under
  reduced motion nothing loads and the poster stays.

## Constraints

- **No third-party requests at all**: fonts, images and scripts are self-hosted. No analytics, no cookies,
  no tracking pixels, no embeds, no consent banner needed.
- Fast on a phone: compressed images in modern formats with fallbacks, explicit width and height, lazy
  loading below the fold.
- Accessible: WCAG AA contrast (the tokens are built for it), alt text, visible keyboard focus, real
  headings, `lang` on every page, `prefers-color-scheme` for dark mode.
- Basics: a `<title>` and description per page and language, an Open Graph image, `sitemap.xml`,
  `robots.txt`, a favicon from the app icon once it exists.

## Languages

English first, then German, Romanian and Russian with the app's Phase 3 translation pass, read by a native
speaker. Keep wording consistent with the app's own strings (`../softfill/Softfill/Localizable.xcstrings`).
In Romanian use the standard forms (o sută, șaizeci, paisprezece, șaisprezece), as the app does.
Write " · " with plain spaces where a line joins two parts (the level lines, the hero note); the build puts a
no-break space before the dot so it never starts a line. The parental gate mock's number in words must match its digits
(3, 4) in every language.

Published 2026-10-13 (every string and both articles; Alex: publish before the native read, fix wording after it):
- **Register**: the app's, informal throughout (du, tu, ты). The handoff's Russian hero draft said «вы»; Alex chose
  «ты» like the app (2026-10-13), for the site and the App Store text alike.
- **Terms** come from the app's catalog: the level names and lines, "Ask a grown-up", the gate card, Settings'
  rows (Restore purchases, Manage subscription, iCloud sync), Fill and Draw, "Inside lines", Gallery. Content
  names (Sunny Meadow, Garden party) come from the drawing's and palette's own names.
- **Apple's names**: Familienfreigabe and Kaufanfrage; Partajare familială and Cerere de cumpărare (Apple's newer
  Romanian help pages); Семейный доступ and «Попросить купить». Apple Account stays "Apple Account" in German,
  "contul Apple" in Romanian, "аккаунт Apple" in Russian. iOS Settings is Einstellungen, Configurări, Настройки.
- **The hero** takes the handoff's drafts where they read better (its titles, ledes and taglines, German
  "Demnächst"), aligned with the app's words ("în contur", not "între linii").
- **The gate mock** spells 347 as Foundation's spell-out does in each language (the app's own formatter); the
  German number carries soft hyphens so it breaks inside the card.
- Article titles hyphenate (`.article-head h1`): "Datenschutzerklärung" and "конфиденциальности" are wider than
  a 390 px screen at 36 px.

## Hosting

- GitHub repo `a7ex-turcan/softfill-web`, created on 2026-10-12 and made **public** the same day (Alex's
  call), because Pages on a private repo needs a paid plan. Everything committed here, including the history
  and this file, is public.
- Pages enabled through the API on 2026-10-12: "Deploy from a branch" (`build_type` legacy), branch `main`,
  folder `/docs`. No GitHub Actions; the committed `docs/` is what gets served, and `docs/.nojekyll` turns
  Jekyll off. Check a build with `gh api repos/a7ex-turcan/softfill-web/pages/builds/latest`.
- `docs/CNAME` contains `softfill.nutrx-labs.com`; the build writes it, so it survives every rebuild, and Pages
  reads the custom domain from it. So `a7ex-turcan.github.io/softfill-web/` redirects to the domain, and the
  site can only be seen there (its links are root-relative too).
- DNS at Cloudflare (nameservers `jeff` and `sonia.ns.cloudflare.com`): a CNAME record `softfill` →
  `a7ex-turcan.github.io`, **DNS only (grey cloud)** until GitHub has issued the HTTPS certificate. Proxying
  through Cloudflare before the certificate exists blocks it. Once `https://softfill.nutrx-labs.com` answers
  with GitHub's certificate, enforce HTTPS:
  `gh api -X PUT repos/a7ex-turcan/softfill-web/pages -F https_enforced=true`.
- Status 2026-10-12: **live at https://softfill.nutrx-labs.com.** The `softfill` CNAME exists (created by Claude
  through the Cloudflare MCP server, DNS only, with a comment saying why) and resolves publicly. GitHub's
  Let's Encrypt certificate covers the domain (it renews it automatically), and HTTPS is enforced, so plain
  HTTP redirects to HTTPS.
- Keep the record **DNS only** for good, not just until the first certificate: GitHub renews the certificate by
  reaching the domain directly, and a static site gains nothing from Cloudflare's proxy.
- If the certificate ever stalls (the Pages API shows no `https_certificate` long after DNS resolves), remove
  and re-add the custom domain, as GitHub's docs say. Through the API: `PUT …/pages` with `"cname": null`, then
  with the domain again. GitHub then commits "Delete CNAME" and "Create CNAME" to `main` itself; that is
  expected. It writes the file without a trailing newline, and so does `build.py`, so `--check` stays green.
- Cloudflare access: the official Cloudflare MCP server (`https://mcp.cloudflare.com/mcp`) is installed in
  Alex's local Claude Code config for this project and signed in as his account. DNS changes still need his
  go-ahead first, like any outward-facing change.
- **Email** (set up 2026-10-12 with Alex's go-ahead): Cloudflare Email Routing receives mail for
  `nutrx-labs.com`. One rule forwards `softfill@nutrx-labs.com` to `alex.turcan@outlook.com`, the Cloudflare
  account's own address, so it needed no verification. The catch-all stays off, so other addresses bounce.
  Enabling it added three MX records (`route1`–`route3.mx.cloudflare.net`), an SPF record
  (`v=spf1 include:_spf.mx.cloudflare.net ~all`) and a `cf2024-1._domainkey` DKIM key. Cloudflare locks them;
  change mail routing in Email Routing, not in DNS. Brevo's sending records are untouched.
  - If mail is ever sent *as* `@nutrx-labs.com` through another service, add its `include:` to that SPF
    record, or it soft-fails.
  - Replies go out from the Outlook address, not `softfill@`. Answering as `softfill@` needs a sending
    service (Brevo is set up for the domain already).
- `nutrx-labs.com` is **verified** for the `a7ex-turcan` account (2026-10-12; GitHub profile settings, Pages),
  so no other GitHub account can claim it or any subdomain, including `www`. The proof is the TXT record
  `_github-pages-challenge-a7ex-turcan` at Cloudflare. Keep it: deleting it unverifies the domain.
- Alex creates the GitHub repo, the Pages settings and the DNS record, or approves each step first. All three
  done on 2026-10-12 with his approval.

## Order of work

1. Repo, Pages and DNS. Start with `build.py`, `base.html` and the English strings producing a one-line
   placeholder Home, so the domain resolves over HTTPS before any real page exists.
2. App icon and wordmark: delivered (see Assets, Brand), and the Home mock now uses them. The Home
   design is approved and in `design_handoff_softfill_web/`; Support, Privacy, Terms and 404 are built from
   the same system (handoff README, "Not designed yet") and shown to Alex before publishing.
3. **Privacy and Support** in English (they gate TestFlight).
4. Home, Terms and 404.
5. German, Romanian and Russian versions. Published 2026-10-13 (see Languages); a native speaker's read is still due.
6. Report the final URLs back to the app session: it wires them into `ExternalLinks.swift` and App Store
   Connect (privacy, support and marketing URL per language, TestFlight test information).

## Working rules

- Keep this file current. When a product fact, price or the privacy story changes in the app, update the
  "Product facts" and "Privacy facts" sections here in the same change as the page that uses them.
- Before committing a page, run `python3 build.py --check` and look at the page at 390 and 1440 wide in
  light and dark mode, served by the local preview server. `tools/screenshots.sh <out-dir> [path ...]` takes
  all four with headless Chrome; read the PNGs back to check them. Two traps it works around: headless Chrome
  never lays a page out narrower than 500 px, so a plain `--window-size=390,…` screenshot is a 500 px page cut
  off on the right (the script loads the page in a 390 px iframe and crops); and `preferredColorScheme=1`
  forces light and `=0` dark, while `--force-dark-mode` does not switch the page. Keep screenshots out of the
  repo (the scratchpad, or ignored PNGs at the root).
- Ask before anything outward-facing: creating the GitHub repo, changing DNS, publishing. Pushing to `main`
  publishes the site.
- Once the repo exists, every change goes through a pull request into `main` with a self-review posted on
  the PR before it merges, the same workflow as the app (`../softfill/CLAUDE.md`, "Pull requests"), except
  that nobody else reviews this repo: decided 2026-10-12, Claude merges its own PRs once the self-review's
  findings are fixed or answered on the PR, `build.py --check` passes and the pages have been looked at.
- Commits: imperative subject under 72 characters, a body that says why. A `.gitignore` keeps out
  `.DS_Store`, `__pycache__/` and screenshots.
- Report what was checked and what was not.
