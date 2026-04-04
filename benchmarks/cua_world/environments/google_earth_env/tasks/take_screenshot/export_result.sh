#!/bin/bash
set -euo pipefail

echo "=== Exporting take_screenshot task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# List any new image files on Desktop
echo "--- Desktop image files ---" >> "$RESULT_FILE"
ls -la /home/ga/Desktop/*.jpg /home/ga/Desktop/*.jpeg /home/ga/Desktop/*.png 2>/dev/null >> "$RESULT_FILE" || echo "No images on Desktop" >> "$RESULT_FILE"

# List any new image files in Pictures
echo "--- Pictures folder ---" >> "$RESULT_FILE"
ls -la /home/ga/Pictures/*.jpg /home/ga/Pictures/*.jpeg /home/ga/Pictures/*.png 2>/dev/null >> "$RESULT_FILE" || echo "No images in Pictures" >> "$RESULT_FILE"

# Check home directory
echo "--- Home directory images ---" >> "$RESULT_FILE"
ls -la /home/ga/*.jpg /home/ga/*.jpeg /home/ga/*.png 2>/dev/null >> "$RESULT_FILE" || echo "No images in home" >> "$RESULT_FILE"

# Capture a screenshot of the current state as backup evidence
scrot /tmp/final_state_screenshot.png 2>/dev/null || true
echo "Final state screenshot saved to /tmp/final_state_screenshot.png" >> "$RESULT_FILE"

# Get image dimensions if any were found
for img in /home/ga/Desktop/*.jpg /home/ga/Desktop/*.png /home/ga/Pictures/*.jpg /home/ga/Pictures/*.png; do
    if [ -f "$img" ]; then
        echo "--- Image info: $img ---" >> "$RESULT_FILE"
        identify "$img" 2>/dev/null >> "$RESULT_FILE" || echo "Could not identify image" >> "$RESULT_FILE"
    fi
done 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
