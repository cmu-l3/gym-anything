#!/bin/bash
# pre_task hook for rotate_image_clockwise on Preview/macOS.
#
# Responsibilities:
#   1. Force-quit any prior Preview so File→Save behavior starts clean.
#   2. Delete any pre-existing input image (anti-gaming: a stale file would
#      let a do-nothing agent inherit a rotated artifact from a previous run).
#   3. Download the canonical source image (NASA Earthrise public-domain
#      thumbnail from Wikimedia Commons), with one fallback URL.
#   4. Record the initial pixel dimensions via `sips` — the verifier uses
#      these as the baseline for the "dimensions swapped after rotation"
#      check, so per-image variation in thumbnail size doesn't matter.
#   5. Record an authoritative task-start Unix timestamp. Sleep briefly so
#      a subsequent Cmd+S clearly produces an mtime > task_start.
#   6. Launch Preview with the image loaded so the agent doesn't need to
#      navigate File→Open. Wait for the window to register.
set -eu

echo "=== Setting up rotate_image_clockwise ==="

INPUT_PATH="$HOME/Documents/preview_rotation_input.png"
INITIAL_DIMS_FILE="/tmp/preview_rotate_initial_dims.json"
INPUT_SHA_FILE="/tmp/preview_rotate_initial_sha256"

# 1) Clean slate: quit Preview if running so the subsequent `open -a Preview`
# below brings up a fresh window without inheriting cached state from a
# previous reset (Edit menu items, modified buffers, last-open files, etc.).
# This is the *clean-slate* pattern, NOT a pre_task-kill convention violation
# — the pre_task ends in the LAUNCHED state (Preview open on the input file),
# which matches the cua_world convention. `osascript ... to quit` is direct
# app-event scripting (not `tell System Events`), so TCC-over-SSH doesn't
# block it; `pkill -x` is a backstop.
osascript -e 'tell application "Preview" to quit' 2>/dev/null || true
sleep 1
pkill -x Preview 2>/dev/null || true
sleep 1

# 2) Remove any stale input (both legacy .jpg and current .png in case
# of a partial earlier run)
rm -f "$HOME/Documents/preview_rotation_input.jpg" \
      "$HOME/Documents/preview_rotation_input.png" 2>/dev/null || true
mkdir -p "$HOME/Documents"

# 3) Download the source image with URL fallback (pattern #7).
#
# Source: Wikimedia Commons "PNG transparency demonstration" — a well-known
# 800×600 PNG demonstrating alpha-channel handling. Released to the public
# domain by author Pierre-Yves "Pmx" Lapersonne. Chosen because:
#   (a) 800×600 is clearly non-square — rotation produces a verifiable
#       dimension swap (800,600) ↔ (600,800).
#   (b) Tiny (~170 KB) — fast download even on rate-limited links.
#   (c) PNG round-trip through Preview's File→Save preserves pixel
#       dimensions; sips can read the post-save file without issue.
#
# Wikimedia blocks curl's default User-Agent on the /thumb/ endpoint
# (returns HTTP 400 with no UA). Set an explicit UA per Wikimedia's
# robot policy. Tested live 2026-05 — both URLs return 200 with a UA.
UA="gym-anything-preview-env/0.1 (https://github.com/anthropics/claude-code; pranjala@andrew.cmu.edu)"
URL1="https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png"
URL2="https://upload.wikimedia.org/wikipedia/en/4/47/PNG_transparency_demonstration_1.png"

DOWNLOADED=0
for url in "$URL1" "$URL2"; do
  echo "[setup] trying $url"
  if /usr/bin/curl -fSL --retry 3 --retry-delay 2 --max-time 60 \
       -A "$UA" -o "$INPUT_PATH" "$url"; then
    DOWNLOADED=1
    echo "[setup] downloaded $(/usr/bin/stat -f %z "$INPUT_PATH") bytes from $url"
    break
  else
    echo "[setup] curl failed for $url"
  fi
done

if [ "$DOWNLOADED" -ne 1 ]; then
  echo "[setup] ERROR: failed to download source image from any fallback URL" >&2
  exit 1
fi

# 4) Record initial dimensions via sips. Output of `sips -g pixelWidth -g
# pixelHeight FILE` looks like:
#   /path/to/file
#     pixelWidth: 640
#     pixelHeight: 655
# Parse with awk; emit JSON for export_result.sh + verifier to consume.
SIPS_OUT=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$INPUT_PATH" 2>/dev/null || true)
WIDTH=$(echo "$SIPS_OUT" | /usr/bin/awk '/pixelWidth/  {print $2}')
HEIGHT=$(echo "$SIPS_OUT" | /usr/bin/awk '/pixelHeight/ {print $2}')

if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
  echo "[setup] ERROR: could not read pixel dimensions of $INPUT_PATH via sips" >&2
  echo "[setup] sips output:" >&2
  echo "$SIPS_OUT" >&2
  exit 1
fi

# Need a non-square image so the rotation check is meaningful. If for some
# reason the source thumbnail returned a square crop, hard-fail with a clear
# message rather than producing an ambiguous task.
if [ "$WIDTH" = "$HEIGHT" ]; then
  echo "[setup] ERROR: source image is square (${WIDTH}x${HEIGHT}); rotation cannot be detected by dimensions alone" >&2
  exit 1
fi

# Initial sha256 — used by export_result.sh to detect "agent saved the file
# even though byte contents didn't change" (a save through Preview re-encodes
# the JPEG, so the hash WILL change after rotation+save; this is a positive
# signal of work being done).
INITIAL_SHA=$(/usr/bin/shasum -a 256 "$INPUT_PATH" | /usr/bin/awk '{print $1}')

/usr/bin/python3 - "$WIDTH" "$HEIGHT" "$INITIAL_SHA" "$INITIAL_DIMS_FILE" << 'PYEOF'
import json, sys
w, h, sha, out_path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(out_path, "w") as f:
    json.dump({"width": w, "height": h, "sha256": sha}, f)
print(f"initial: width={w} height={h} sha256={sha[:16]}…")
PYEOF
echo "$INITIAL_SHA" > "$INPUT_SHA_FILE"

# 5) Sleep, then record task_start AFTER the download so any subsequent save
# by Preview will have mtime strictly greater than task_start.
sleep 2
date +%s > /tmp/preview_rotate_task_start_timestamp
echo "task_start_unix=$(cat /tmp/preview_rotate_task_start_timestamp)"

# 6) Launch Preview with the image, wait for window to register.
# The bundle-path regex `Preview\.app` matches the line
# `bundle path="/System/Applications/Preview.app"` in lsappinfo output.
# The Safari-style `'AppName( |$)'` pattern doesn't work for Preview —
# Preview has no helper processes with a quoted-name space suffix
# (see 12_macos_environments.md "lsappinfo Regex" section).
echo "[setup] launching Preview with $INPUT_PATH"
open -a Preview "$INPUT_PATH"
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Preview\.app'; then
    echo "[setup] Preview registered after ${i}s"
    break
  fi
  sleep 1
done
sleep 3   # let the image-load animation settle before screenshots

# Start-state screenshot (for trajectory archive).
/usr/sbin/screencapture -x /tmp/preview_rotate_task_start.png 2>/dev/null || true

echo "=== rotate_image_clockwise setup complete ==="
echo "Preview is open on a landscape image. Agent should rotate 90° clockwise and save in place."
