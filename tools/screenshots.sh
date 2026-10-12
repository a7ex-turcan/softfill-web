#!/bin/sh
# Screenshots pages at 390 and 1440 wide, light and dark, from the local preview server.
#
#   python3 build.py && python3 -m http.server 8000 -d docs &
#   tools/screenshots.sh <out-dir> [path ...]        (default paths: every English page)
#
# Headless Chrome will not lay a page out narrower than 500 px, so a plain --window-size=390 screenshot is a
# 500 px page cut off on the right. For 390 the page loads in a 390 px iframe centered in a wider window, and
# sips (which always crops around the center) cuts the frame back out.
# Light is preferredColorScheme=1, dark is 0; headless Chrome ignores --force-dark-mode for pages.
OUT="${1:?usage: tools/screenshots.sh <out-dir> [path ...]}"; shift
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASE="${BASE:-http://localhost:8000}"
PATHS="${*:-/ /privacy /terms /support /404.html}"
HEIGHT_390="${HEIGHT_390:-4800}"
HEIGHT_1440="${HEIGHT_1440:-3200}"
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

shoot() { # width height scheme url out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --force-device-scale-factor=1 \
    --blink-settings=preferredColorScheme=$3 --window-size=$1,$2 --virtual-time-budget=4000 \
    --screenshot="$5" "$4" >/dev/null 2>&1 || true
}

for p in $PATHS; do
  name=$(echo "$p" | sed 's#^/$#home#; s#/$##; s#^/##; s#/#-#g; s#\.html$##')
  for scheme in light dark; do
    [ "$scheme" = light ] && pref=1 || pref=0
    out="$OUT/$name-1440-$scheme.png"
    shoot 1440 "$HEIGHT_1440" $pref "$BASE$p" "$out"
    [ -s "$out" ] && echo "$out" || echo "FAILED $p 1440 $scheme"

    wrapper="$TMP/frame.html"
    printf '<!doctype html><html><head><style>html,body{margin:0}iframe{display:block;border:0;margin:0 auto;width:390px;height:%spx}</style></head><body><iframe src="%s"></iframe></body></html>' \
      "$HEIGHT_390" "$BASE$p" > "$wrapper"
    out="$OUT/$name-390-$scheme.png"
    shoot 800 "$HEIGHT_390" $pref "file://$wrapper" "$out"
    if [ -s "$out" ]; then sips -c "$HEIGHT_390" 390 "$out" >/dev/null 2>&1; echo "$out"; else echo "FAILED $p 390 $scheme"; fi
  done
done
