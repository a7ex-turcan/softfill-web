#!/bin/sh
# Renders the Home page's art (tools/art/recipe.json) from the app repo checked out at ../softfill.
#   tools/art/build.sh                 every output
#   tools/art/build.sh tap draw        only these
# Then rebuild the site: python3 build.py
set -e
cd "$(dirname "$0")/../.."
BIN="${TMPDIR:-/tmp}/softfill-render"
swiftc -O tools/art/render.swift -o "$BIN"
"$BIN" tools/art/recipe.json "$@"
