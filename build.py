#!/usr/bin/env python3
"""Builds the Softfill website: src/templates + src/strings + src/articles → docs/.

Standard library only; runs on the macOS system Python (3.9). See CLAUDE.md, "Build".

    python3 build.py                  build docs/ (a string missing in any language fails the build)
    python3 build.py --allow-missing  fall back to English for missing strings and list every gap
    python3 build.py --check          rebuild into a temporary folder and fail if docs/ differs
"""
import argparse
import filecmp
import hashlib
import html
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "docs"

DOMAIN = "softfill.nutrx-labs.com"
SITE = f"https://{DOMAIN}"
APP_STORE_URL = "https://apps.apple.com/app/id6820982967"
APP_STORE_ID = "6820982967"

# Every language the site will have, in switcher order. A language is published (built, listed in the switcher,
# hreflang and the sitemap) once src/strings/<lang>.json exists; English always is.
ALL_LANGS = ["en", "de", "ro", "ru"]
DEFAULT_LANG = "en"
LANGS = [lang for lang in ALL_LANGS if lang == DEFAULT_LANG or (SRC / "strings" / f"{lang}.json").exists()]
# Native names and the code the switcher shows; these never need translating.
LANG_NAMES = {"en": ("English", "EN"), "de": ("Deutsch", "DE"), "ro": ("Română", "RO"), "ru": ("Русский", "RU")}
OG_LOCALES = {"en": "en_US", "de": "de_DE", "ro": "ro_RO", "ru": "ru_RU"}

# page id → (template, URL segment). The segment is final: the app and App Store Connect link to it.
PAGES = {
    "home": ("home.html", ""),
    "privacy": ("article.html", "privacy"),
    "terms": ("article.html", "terms"),
    "support": ("support.html", "support"),
}
ARTICLES = {"privacy", "terms"}

# Product state. Flip these when the app changes; the templates pick strings and partials by them.
# CLAUDE.md, "Product facts", says when each one is allowed to change.
APP_LIVE = False        # App Store badge and Smart App Banner, instead of "Coming soon to the App Store"
IPHONE_SHIPPED = False  # the "iPad and iPhone" section copy

# A `{{> name }}` in a template resolves to one of these partials by product state.
PARTIAL_OVERRIDES = {
    "store_cta": "store_cta_live" if APP_LIVE else "store_cta_soon",
    "store_cta_small": "store_cta_small_live" if APP_LIVE else "store_cta_small_soon",
    "app_meta": "app_meta_live" if APP_LIVE else "nothing",
    "lang_switcher": "lang_switcher" if len(LANGS) > 1 else "nothing",
    "devices_phone_badge": "nothing" if IPHONE_SHIPPED else "devices_phone_badge",
}
# A `{{ key }}` for one of these keys reads the first string when the flag is set, else the second.
STRING_SWITCHES = [
    (IPHONE_SHIPPED, {
        "devices_title": ("devices_title_shipped", "devices_title_soon"),
        "devices_text": ("devices_text_shipped", "devices_text_soon"),
    }),
]

PLACEHOLDER = re.compile(r"\{\{\s*(>?)\s*([A-Za-z0-9_./-]+)\s*\}\}")


class BuildError(Exception):
    pass


# --- inputs -----------------------------------------------------------------------------------

def load_strings(allow_missing):
    """Returns {lang: {key: value}}; every language ends up with exactly the English key set."""
    strings = {}
    for lang in LANGS:
        path = SRC / "strings" / f"{lang}.json"
        if not path.exists():
            raise BuildError(f"missing strings file {path.relative_to(ROOT)}")
        with path.open(encoding="utf-8") as f:
            strings[lang] = json.load(f)
    en = strings[DEFAULT_LANG]
    problems, gaps = [], []
    for lang in LANGS[1:]:
        table = strings[lang]
        extra = sorted(set(table) - set(en))
        if extra:
            problems.append(f"{lang}.json has keys that en.json does not: {', '.join(extra)}")
        missing = sorted(set(en) - set(table))
        if missing:
            if allow_missing:
                gaps.append(f"{lang}.json falls back to English for: {', '.join(missing)}")
                for key in missing:
                    table[key] = en[key]
            else:
                problems.append(f"{lang}.json is missing: {', '.join(missing)}")
    if problems:
        raise BuildError("\n".join(problems))
    for gap in gaps:
        print(gap, file=sys.stderr)
    return strings


def load_article(page, lang, allow_missing):
    path = SRC / "articles" / f"{page}.{lang}.html"
    if not path.exists():
        if allow_missing and lang != DEFAULT_LANG:
            print(f"{path.name} is missing; falling back to the English article", file=sys.stderr)
            path = SRC / "articles" / f"{page}.{DEFAULT_LANG}.html"
        if not path.exists():
            raise BuildError(f"missing article {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8").strip()


def read_template(name):
    path = SRC / "templates" / name
    if not path.exists():
        raise BuildError(f"missing template {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


# --- rendering --------------------------------------------------------------------------------

def render(text, ctx, where, depth=0):
    """Fills `{{ key }}` from ctx (escaped unless the key ends in _html) and `{{> name }}` from partials."""
    if depth > 20:
        raise BuildError(f"partials nest too deeply in {where}")

    def sub(match):
        is_partial, key = match.group(1), match.group(2)
        if is_partial:
            name = PARTIAL_OVERRIDES.get(key, key)
            partial = read_template(f"partials/{name}.html")
            return render(partial, ctx, f"partials/{name}.html", depth + 1).strip()
        for holds, switches in STRING_SWITCHES:
            if key in switches:
                key = switches[key][0 if holds else 1]
        if key not in ctx:
            raise BuildError(f"{where}: no string or value for {{{{ {key} }}}}")
        value = ctx[key]
        if key.endswith("_html"):
            return value
        return html.escape(str(value), quote=True)

    return PLACEHOLDER.sub(sub, text)


def url_for(page, lang):
    segment = PAGES[page][1]
    prefix = "" if lang == DEFAULT_LANG else f"/{lang}"
    if segment == "":
        return f"{prefix}/"
    return f"{prefix}/{segment}"


def alternates_html(page):
    if len(LANGS) < 2:
        return ""
    lines = []
    for lang in LANGS:
        lines.append(f'<link rel="alternate" hreflang="{lang}" href="{SITE}{url_for(page, lang)}">')
    lines.append(f'<link rel="alternate" hreflang="x-default" href="{SITE}{url_for(page, DEFAULT_LANG)}">')
    return "\n".join(lines)


def lang_menu_html(page, current, check_icon):
    rows = []
    for lang in LANGS:
        name, code = LANG_NAMES[lang]
        is_current = lang == current
        classes = "lang-row is-current" if is_current else "lang-row"
        aria = ' aria-current="true"' if is_current else ""
        check = check_icon if is_current else ""
        rows.append(
            f'<a class="{classes}" href="{url_for(page, lang)}" hreflang="{lang}" lang="{lang}"{aria}>'
            f'<span class="lang-row-name">{name}</span><span class="lang-row-code">{code}</span>'
            f'<span class="lang-row-check">{check}</span></a>'
        )
    return "\n".join(rows)


def page_context(page, lang, strings, css_url, js_url, article=None):
    ctx = dict(strings[lang])
    prefix = "" if lang == DEFAULT_LANG else f"/{lang}"
    ctx.update({
        "lang": lang,
        "page": page,
        "prefix": prefix,
        "home_url": url_for("home", lang),
        "canonical": SITE + (url_for(page, lang) if page in PAGES else "/404.html"),
        "canonical_html": (f'<link rel="canonical" href="{SITE}{url_for(page, lang)}">' if page in PAGES else ""),
        "site_url": SITE,
        "og_locale": OG_LOCALES[lang],
        "og_image": f"{SITE}/assets/img/og/softfill-og-{lang}.png",
        "switcher_code": LANG_NAMES[lang][1],
        "switcher_name": LANG_NAMES[lang][0],
        "css_url": css_url,
        "js_url": js_url,
        "app_store_url": APP_STORE_URL,
        "app_store_id": APP_STORE_ID,
        "alternates_html": alternates_html(page) if page != "notfound" else "",
        "lang_menu_html": lang_menu_html(page if page != "notfound" else "home", lang,
                                         read_template("partials/icon/check.html").strip()),
    })
    ctx["title"] = ctx[f"{page}_title"]
    ctx["description"] = ctx[f"{page}_description"]
    if article is not None:
        # The article template is shared by Privacy and Terms; these pick the page's own strings.
        ctx["article_html"] = article
        ctx["article_heading"] = ctx[f"{page}_heading"]
        ctx["article_updated"] = ctx[f"{page}_updated"]
        ctx["article_updated_iso"] = ctx[f"{page}_updated_iso"]
    return ctx


def build_page(page, lang, strings, css_url, js_url, out_dir, allow_missing):
    template, _segment = PAGES[page]
    article = load_article(page, lang, allow_missing) if page in ARTICLES else None
    ctx = page_context(page, lang, strings, css_url, js_url, article)
    ctx["content_html"] = render(read_template(template), ctx, template)
    document = render(read_template("base.html"), ctx, "base.html")
    target = out_dir / url_for(page, lang).lstrip("/") / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(document, encoding="utf-8")


def build_not_found(strings, css_url, js_url, out_dir):
    ctx = page_context("notfound", DEFAULT_LANG, strings, css_url, js_url)
    ctx["content_html"] = render(read_template("404.html"), ctx, "404.html")
    (out_dir / "404.html").write_text(render(read_template("base.html"), ctx, "base.html"), encoding="utf-8")


# --- site files -------------------------------------------------------------------------------

def content_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()[:8]


def copy_assets(out_dir):
    shutil.copytree(SRC / "assets", out_dir / "assets", ignore=shutil.ignore_patterns(".DS_Store"))


def write_sitemap(out_dir):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'
             ' xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    for page in PAGES:
        for lang in LANGS:
            lines.append("  <url>")
            lines.append(f"    <loc>{SITE}{url_for(page, lang)}</loc>")
            for other in (LANGS if len(LANGS) > 1 else []):
                lines.append(f'    <xhtml:link rel="alternate" hreflang="{other}" href="{SITE}{url_for(page, other)}"/>')
            if len(LANGS) > 1:
                lines.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE}{url_for(page, DEFAULT_LANG)}"/>')
            lines.append("  </url>")
    lines.append("</urlset>")
    (out_dir / "sitemap.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_site_files(out_dir):
    (out_dir / "CNAME").write_text(DOMAIN + "\n", encoding="utf-8")
    (out_dir / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8")
    (out_dir / ".nojekyll").write_text("", encoding="utf-8")
    write_sitemap(out_dir)


# --- checks -----------------------------------------------------------------------------------

LOCAL_REF = re.compile(r'(?:href|src|poster)="(/[^"#?\s]*)(?:[?#][^"]*)?"')
SRCSET = re.compile(r'srcset="([^"]*)"')


def local_refs(text):
    """Root-relative URLs in href, src and poster attributes, and every candidate of every srcset."""
    refs = set(LOCAL_REF.findall(text))
    for value in SRCSET.findall(text):
        for candidate in value.split(","):
            url = candidate.strip().split(" ")[0].split("?")[0].split("#")[0]
            if url.startswith("/"):
                refs.add(url)
    return refs


def check_links(out_dir):
    """Every root-relative href/src in the output must point at a file the build wrote."""
    problems = []
    for page in sorted(out_dir.rglob("*.html")):
        for ref in local_refs(page.read_text(encoding="utf-8")):
            target = out_dir / ref.lstrip("/")
            if ref.endswith("/"):
                target = target / "index.html"
            if not target.exists() and not (target / "index.html").exists():
                problems.append(f"{page.relative_to(out_dir)} links to {ref}, which the build did not write")
    if APP_LIVE:
        for lang in LANGS:
            badge = out_dir / "assets" / "img" / "badges" / f"app-store-{lang}.svg"
            if not badge.exists():
                problems.append(f"APP_LIVE is set but {badge.relative_to(out_dir)} is missing")
    if problems:
        raise BuildError("\n".join(problems))


def differences(a, b, rel=""):
    cmp = filecmp.dircmp(a, b, ignore=[".DS_Store"])
    found = [f"only in docs/: {rel}{name}" for name in cmp.left_only]
    found += [f"missing from docs/: {rel}{name}" for name in cmp.right_only]
    _match, mismatch, errors = filecmp.cmpfiles(a, b, cmp.common_files, shallow=False)
    found += [f"differs: {rel}{name}" for name in mismatch + errors]
    for name in cmp.common_dirs:
        found += differences(a / name, b / name, f"{rel}{name}/")
    return found


# --- main -------------------------------------------------------------------------------------

def build(out_dir, allow_missing):
    strings = load_strings(allow_missing)
    out_dir.mkdir(parents=True, exist_ok=True)
    copy_assets(out_dir)
    css = SRC / "assets" / "css" / "site.css"
    js = SRC / "assets" / "js" / "site.js"
    css_url = f"/assets/css/site.css?v={content_hash(css)}"
    js_url = f"/assets/js/site.js?v={content_hash(js)}"
    for page in PAGES:
        for lang in LANGS:
            build_page(page, lang, strings, css_url, js_url, out_dir, allow_missing)
    build_not_found(strings, css_url, js_url, out_dir)
    write_site_files(out_dir)
    check_links(out_dir)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--allow-missing", action="store_true", help="fall back to English for missing strings")
    parser.add_argument("--check", action="store_true", help="fail if docs/ is not what the build produces")
    args = parser.parse_args()
    try:
        if args.check:
            with tempfile.TemporaryDirectory() as tmp:
                fresh = Path(tmp) / "docs"
                build(fresh, args.allow_missing)
                if not OUT.exists():
                    raise BuildError("docs/ does not exist; run python3 build.py")
                diffs = differences(OUT, fresh)
                if diffs:
                    raise BuildError("docs/ is stale; run python3 build.py and commit the result:\n  " + "\n  ".join(diffs))
            print("docs/ is up to date")
        else:
            # Build next to docs/ and swap it in only on success, so a failed build leaves docs/ as it was.
            with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
                fresh = Path(tmp) / "docs"
                build(fresh, args.allow_missing)
                if OUT.exists():
                    shutil.rmtree(OUT)
                fresh.rename(OUT)
            pages = sum(1 for _ in OUT.rglob("*.html"))
            print(f"built {pages} pages into {OUT.relative_to(ROOT)}/")
    except BuildError as error:
        print(f"build failed:\n{error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
