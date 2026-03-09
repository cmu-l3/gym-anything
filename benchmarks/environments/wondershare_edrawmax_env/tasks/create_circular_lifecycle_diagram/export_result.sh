#!/bin/bash
set -e
echo "=== Exporting create_circular_lifecycle_diagram results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EDDX_FILE="/home/ga/Documents/sdlc_lifecycle.eddx"
PNG_FILE="/home/ga/Documents/sdlc_lifecycle.png"

# Take final screenshot immediately
echo "Capturing final state..."
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# --- Check 1: EDDX file analysis ---
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_MTIME="0"
if [ -f "$EDDX_FILE" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c%s "$EDDX_FILE" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c%Y "$EDDX_FILE" 2>/dev/null || echo "0")
fi

# --- Check 2: PNG file analysis ---
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_MTIME="0"
PNG_WIDTH="0"
PNG_HEIGHT="0"

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c%s "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c%Y "$PNG_FILE" 2>/dev/null || echo "0")
    
    # Get dimensions if ImageMagick is available
    if command -v identify >/dev/null 2>&1; then
        DIMENSIONS=$(identify -format "%wx%h" "$PNG_FILE" 2>/dev/null || echo "0x0")
        PNG_WIDTH=$(echo "$DIMENSIONS" | cut -dx -f1)
        PNG_HEIGHT=$(echo "$DIMENSIONS" | cut -dx -f2)
    fi
fi

# --- Check 3: Timestamps relative to task start ---
EDDX_NEW="false"
PNG_NEW="false"

if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
    EDDX_NEW="true"
fi

if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
    PNG_NEW="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "eddx_exists": $EDDX_EXISTS,
  "eddx_size": $EDDX_SIZE,
  "eddx_is_new": $EDDX_NEW,
  "png_exists": $PNG_EXISTS,
  "png_size": $PNG_SIZE,
  "png_is_new": $PNG_NEW,
  "png_width": $PNG_WIDTH,
  "png_height": $PNG_HEIGHT,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"