#!/usr/bin/env bash
# Capture one page at 2x with agent-browser and list element boxes for the callouts.
#
# Usage:
#   shoot.sh URL OUT.png [options]          a live page (http/https/file URL)
#   shoot.sh FRAGMENT.html OUT.png --css APP.css [options]
#                                           an HTML fragment, wrapped in a page with that CSS
# Options:
#   --css FILE        compiled app stylesheet; required for a fragment
#   --base URL        <base href> for the wrapper, so font and image URLs resolve
#   --body-class STR  class on <body> (default "bg-background text-foreground")
#   --wrap-class STR  class on the wrapper div (default "mx-auto max-w-4xl p-6")
#   --width N --height N   viewport in CSS px (default 1440x900)
#   --scale N         device scale factor (default 2)
#   --full            capture the full page: the viewport grows to the page height,
#                     so the boxes cover the whole page in page coordinates
#   --session NAME    reuse an agent-browser session (for example a logged-in one);
#                     the script leaves it open. Without it, the script uses a new
#                     session and closes it at the end.
#   --wait MS         wait after load (default 1500)
# Writes OUT.png and OUT.boxes.txt. Boxes are CSS px, the unit annotate.py expects.
# A fragment also writes OUT.page.html, the wrapper page that was captured.
# Needs agent-browser and jq.
set -euo pipefail

src=${1:?source URL or fragment}
out=${2:?output png}
shift 2
css="" base="" body_class="bg-background text-foreground" wrap_class="mx-auto max-w-4xl p-6"
width=1440 height=900 scale=2 full="" session="" wait=1500
while (($#)); do
  case $1 in
    --css) css=$2; shift ;;
    --base) base=$2; shift ;;
    --body-class) body_class=$2; shift ;;
    --wrap-class) wrap_class=$2; shift ;;
    --width) width=$2; shift ;;
    --height) height=$2; shift ;;
    --scale) scale=$2; shift ;;
    --full) full="--full" ;;
    --session) session=$2; shift ;;
    --wait) wait=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ -z $session ]]; then
  session="shots-$$"
  trap 'agent-browser --session "$session" close >/dev/null 2>&1 || true' EXIT
fi
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
ab() { agent-browser --session "$session" "$@"; }

if [[ $src =~ ^(https?|file):// ]]; then
  url=$src
else
  [[ -n $css ]] || { echo "--css is required for a fragment" >&2; exit 2; }
  page="${out%.png}.page.html"
  css_abs=$(cd "$(dirname "$css")" && pwd)/$(basename "$css")
  {
    echo '<!doctype html><html><head><meta charset="utf-8">'
    [[ -n $base ]] && echo "<base href=\"$base\">"
    echo "<link rel=\"stylesheet\" href=\"file://$css_abs\">"
    echo '<style>html{scrollbar-width:none}html::-webkit-scrollbar{display:none}</style></head>'
    echo "<body class=\"$body_class\"><div class=\"$wrap_class\">"
    cat "$src"
    echo '</div></body></html>'
  } >"$page"
  url="file://$page"
fi

ab set viewport "$width" "$height" "$scale" >/dev/null
ab open "$url" >/dev/null
ab wait "$wait" >/dev/null
# Hide the Next.js dev overlay badge; it is not part of the product.
ab eval "document.head.insertAdjacentHTML('beforeend','<style>nextjs-portal{display:none!important}</style>')" >/dev/null
if [[ -n $full ]]; then
  # Grow the viewport to the page, so the boxes and the capture share page coordinates.
  page_height=$(ab eval "document.documentElement.scrollHeight" | jq -r .)
  ab set viewport "$width" "$page_height" "$scale" >/dev/null
  ab eval "window.scrollTo(0, 0)" >/dev/null
  ab wait 300 >/dev/null
fi
ab screenshot $full "$out" >/dev/null
ab eval "$(cat "$here/boxes.js")" | jq -r . >"${out%.png}.boxes.txt"
echo "$out"
echo "${out%.png}.boxes.txt"
