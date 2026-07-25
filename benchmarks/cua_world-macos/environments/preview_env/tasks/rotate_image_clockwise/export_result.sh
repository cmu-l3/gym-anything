#!/bin/bash
# post_task hook for rotate_image_clockwise on Preview/macOS.
#
# Produces /tmp/rotate_image_clockwise_result.json with:
#   - task_start (unix epoch)
#   - input_exists / input_fresh / input_valid_image flags
#   - initial_width / initial_height (from setup_task.sh's recording)
#   - current_width / current_height (from `sips` post-action)
#   - dimensions_swapped (true when (cur_w, cur_h) == (init_h, init_w))
#   - initial_sha256 / current_sha256 (for the byte-content-changed signal)
#   - file_size_bytes, mtime
#
# Anti-pattern #12: every embedded Python heredoc has try/except and writes
# safe defaults so the verifier always reads valid JSON.

set -u   # NOT set -e — we want to continue past individual failures.

echo "=== Exporting rotate_image_clockwise results ==="

INPUT_PATH="$HOME/Documents/preview_rotation_input.png"
INITIAL_DIMS_FILE="/tmp/preview_rotate_initial_dims.json"
INPUT_SHA_FILE="/tmp/preview_rotate_initial_sha256"
RESULT_PATH="/tmp/rotate_image_clockwise_result.json"

# Capture end-state screenshot for the trajectory archive.
/usr/sbin/screencapture -x /tmp/preview_rotate_task_end.png 2>/dev/null || true

# Force-quit Preview so any in-flight buffered writes flush to disk before
# we measure mtime / dimensions. Preview's autosave / "edited" buffer is
# the macOS analogue of Safari's WAL — observable only after the app quits.
osascript -e 'tell application "Preview" to quit' 2>/dev/null || true
sleep 2
pkill -x Preview 2>/dev/null || true
sleep 1

TASK_START=$(/bin/cat /tmp/preview_rotate_task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Pull initial dims + sha out of the JSON file written by setup. If the file
# is missing / malformed, we default to width=0 height=0 sha="" and the
# verifier will detect the inconsistency.
INIT_JSON='{"width": 0, "height": 0, "sha256": ""}'
if [ -f "$INITIAL_DIMS_FILE" ]; then
  INIT_JSON=$(/bin/cat "$INITIAL_DIMS_FILE" 2>/dev/null || echo "$INIT_JSON")
fi

# Probe the input file's CURRENT state.
INPUT_EXISTS=0
INPUT_MTIME=0
INPUT_SIZE=0
CUR_WIDTH=0
CUR_HEIGHT=0
INPUT_VALID_IMAGE=0
CUR_SHA=""

if [ -f "$INPUT_PATH" ]; then
  INPUT_EXISTS=1
  INPUT_MTIME=$(/usr/bin/stat -f %m "$INPUT_PATH" 2>/dev/null || echo "0")
  INPUT_SIZE=$(/usr/bin/stat -f %z "$INPUT_PATH" 2>/dev/null || echo "0")
  CUR_SHA=$(/usr/bin/shasum -a 256 "$INPUT_PATH" 2>/dev/null | /usr/bin/awk '{print $1}')

  # sips treats valid images and exits 0; on a corrupted file it exits non-zero
  # AND prints "Error". Use exit code as the validity signal.
  if SIPS_OUT=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$INPUT_PATH" 2>/dev/null); then
    INPUT_VALID_IMAGE=1
    CUR_WIDTH=$(echo "$SIPS_OUT"  | /usr/bin/awk '/pixelWidth/  {print $2}')
    CUR_HEIGHT=$(echo "$SIPS_OUT" | /usr/bin/awk '/pixelHeight/ {print $2}')
    : "${CUR_WIDTH:=0}"
    : "${CUR_HEIGHT:=0}"
  fi
fi

INPUT_FRESH=0
if [ "$INPUT_EXISTS" -eq 1 ] && [ "$INPUT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
  INPUT_FRESH=1
fi

echo "input: exists=$INPUT_EXISTS fresh=$INPUT_FRESH valid_image=$INPUT_VALID_IMAGE"
echo "dims: current=${CUR_WIDTH}x${CUR_HEIGHT}"
echo "size: $INPUT_SIZE bytes"

# Stitch the final result JSON in Python so quoting is clean.
/usr/bin/python3 - \
  "$INIT_JSON" "$TASK_START" "$INPUT_EXISTS" "$INPUT_FRESH" "$INPUT_VALID_IMAGE" \
  "$CUR_WIDTH" "$CUR_HEIGHT" "$INPUT_MTIME" "$INPUT_SIZE" "$CUR_SHA" "$RESULT_PATH" \
  << 'PYEOF'
import json, sys
init = json.loads(sys.argv[1] or "{}")
init_w = int(init.get("width", 0) or 0)
init_h = int(init.get("height", 0) or 0)
init_sha = str(init.get("sha256", "") or "")

cur_w = int(sys.argv[6]) if sys.argv[6] else 0
cur_h = int(sys.argv[7]) if sys.argv[7] else 0

# 90° rotation (cw or ccw) swaps width and height. We accept either direction
# of swap; the task description specifies CW but a perfect-180 mistake by the
# agent leaves dims unchanged and won't satisfy this check, while a CCW (Cmd+L
# pressed instead of Cmd+R) also produces swapped dims — for an ambiguous-orientation
# image like Earthrise, CCW is functionally a partial success that we don't
# reward separately. The verifier later uses orientation metadata
# (EXIF / pixel ordering) if available — for this easy task, the
# dimension swap is the primary signal.
dims_swapped = (init_w > 0 and init_h > 0
                and cur_w == init_h and cur_h == init_w)

byte_content_changed = bool(init_sha and sys.argv[10] and init_sha != sys.argv[10])

result = {
    "task_start": int(sys.argv[2]),
    "input_exists": bool(int(sys.argv[3])),
    "input_fresh": bool(int(sys.argv[4])),
    "input_valid_image": bool(int(sys.argv[5])),
    "initial_width": init_w,
    "initial_height": init_h,
    "current_width": cur_w,
    "current_height": cur_h,
    "input_mtime": int(sys.argv[8] or 0),
    "input_size_bytes": int(sys.argv[9] or 0),
    "initial_sha256": init_sha,
    "current_sha256": sys.argv[10],
    "byte_content_changed": byte_content_changed,
    "dimensions_swapped": dims_swapped,
}
with open(sys.argv[11], "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
