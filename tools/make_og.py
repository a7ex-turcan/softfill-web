#!/usr/bin/env python3
"""Renders the Open Graph image for every language into src/assets/img/og/ with headless Chrome.

Run it after the hero strings change: python3 tools/make_og.py. Uses only the site's own fonts and brand
files, and the finished Sunny Meadow from tools/art (tools/art/build.sh og-art renders it into the
git-ignored tools/art/out/); nothing is fetched from the network.
"""
import html
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
LANGS = ["en", "de", "ro", "ru"]
WIDTH, HEIGHT = 1200, 630

PAGE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<style>
@font-face {{ font-family: Nunito; font-weight: 400 900; src: url("{fonts}/nunito-latin.woff2") format("woff2"); unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD; }}
@font-face {{ font-family: Nunito; font-weight: 400 900; src: url("{fonts}/nunito-latin-ext.woff2") format("woff2"); unicode-range: U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF; }}
@font-face {{ font-family: Nunito; font-weight: 400 900; src: url("{fonts}/nunito-cyrillic.woff2") format("woff2"); unicode-range: U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116; }}
@font-face {{ font-family: Nunito; font-weight: 400 900; src: url("{fonts}/nunito-cyrillic-ext.woff2") format("woff2"); unicode-range: U+0460-052F,U+1C80-1C8A,U+20B4,U+2DE0-2DFF,U+A640-A69F,U+FE2E-FE2F; }}
html, body {{ margin: 0; }}
body {{
  width: {w}px; height: {h}px; overflow: hidden; background: #FBFAF7; color: #1C1F25;
  font-family: Nunito, ui-rounded, "SF Pro Rounded", system-ui, sans-serif; font-weight: 500;
  -webkit-font-smoothing: antialiased;
}}
.card {{ position: absolute; inset: 0; padding: 72px 80px; display: flex; flex-direction: column; justify-content: space-between; }}
.lockup {{ display: flex; align-items: center; gap: 22px; }}
.lockup img.icon {{ width: 88px; height: 88px; border-radius: 20px; box-shadow: 0 0 0 1px rgba(28,31,37,.1), 0 8px 24px rgba(28,31,37,.12); }}
.lockup img.wordmark {{ height: 38px; }}
.tag {{ margin-top: 6px; font-size: 22px; font-weight: 700; color: #5A5E65; }}
h1 {{ margin: 0; font-size: 70px; font-weight: 800; letter-spacing: -0.035em; line-height: 1.02; max-width: 560px; text-wrap: balance; hyphens: auto; }}
.note {{ font-size: 24px; font-weight: 700; color: #5A5E65; max-width: 560px; }}
.art {{ position: absolute; right: 64px; top: 50%; width: 470px; aspect-ratio: 3 / 2; margin-top: -157px;
  border-radius: 22px; overflow: hidden; background: #fff; transform: rotate(-2deg);
  box-shadow: 0 0 0 1px rgba(28,31,37,.06), 0 2px 6px rgba(28,31,37,.08), 0 24px 56px rgba(28,31,37,.18); }}
.art img {{ width: 100%; height: 100%; display: block; }}
</style>
</head>
<body>
<div class="art"><img src="{art}" alt=""></div>
<div class="card">
  <div class="lockup">
    <img class="icon" src="{brand}/AppIcon-light.svg" alt="">
    <div>
      <img class="wordmark" src="{brand}/softfill-wordmark-ink.svg" alt="Softfill">
      <div class="tag">{tagline}</div>
    </div>
  </div>
  <h1>{title}</h1>
  <div class="note">{note}</div>
</div>
</body>
</html>
"""


def main():
    out_dir = ROOT / "src" / "assets" / "img" / "og"
    out_dir.mkdir(parents=True, exist_ok=True)
    fonts = (ROOT / "src" / "assets" / "fonts").as_uri()
    brand = (ROOT / "src" / "assets" / "img" / "brand").as_uri()
    art_path = ROOT / "tools" / "art" / "out" / "og-meadow-960.jpg"
    if not art_path.exists():
        sys.exit("missing tools/art/out/og-meadow-960.jpg: run tools/art/build.sh og-art first")
    art = art_path.as_uri()
    for lang in LANGS:
        path = ROOT / "src" / "strings" / f"{lang}.json"
        if not path.exists():
            print(f"{lang}: no strings yet, skipped", file=sys.stderr)
            continue
        strings = json.loads(path.read_text(encoding="utf-8"))
        page = PAGE.format(lang=lang, w=WIDTH, h=HEIGHT, fonts=fonts, brand=brand, art=art,
                           tagline=html.escape(strings["hero_tagline"]), title=html.escape(strings["hero_title"]),
                           note=html.escape(strings["hero_note"]))
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / f"og-{lang}.html"
            source.write_text(page, encoding="utf-8")
            target = out_dir / f"softfill-og-{lang}.png"
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                            "--force-device-scale-factor=1", f"--window-size={WIDTH},{HEIGHT}",
                            "--blink-settings=preferredColorScheme=1", f"--screenshot={target}", source.as_uri()],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"wrote {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
