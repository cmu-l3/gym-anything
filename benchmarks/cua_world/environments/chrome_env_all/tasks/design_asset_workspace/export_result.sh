#!/bin/bash
set -euo pipefail

echo "=== Exporting Design Asset Workspace Result ==="

# Record export start time
date +%s > /tmp/task_end_time.txt

# Take final screenshot (for VLM verification)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to ensure ALL state (Flags, Preferences, Bookmarks) flushes to disk
echo "Signaling Chrome to exit and flush state to disk..."
pkill -15 -f "google-chrome" 2>/dev/null || true
pkill -15 -f "chrome.*remote-debugging-port" 2>/dev/null || true

# Wait for Chrome to write files (Local State and Preferences can take a moment)
sleep 4

# Force kill if still lingering
pkill -9 -f "google-chrome" 2>/dev/null || true

# Build a small metadata result file
OUTPUT_DIR="/home/ga/projects/design-assets"
JSON_EXISTS=$( [ -f "$OUTPUT_DIR/brand_color_palette.json" ] && echo "true" || echo "false" )
SVG_EXISTS=$( [ -f "$OUTPUT_DIR/icon_sprite_sheet.svg" ] && echo "true" || echo "false" )
PDF_EXISTS=$( [ -f "$OUTPUT_DIR/typography_guide.pdf" ] && echo "true" || echo "false" )

cat > /tmp/task_result.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end_time": $(cat /tmp/task_end_time.txt 2>/dev/null || echo "0"),
    "files_downloaded": {
        "brand_color_palette.json": $JSON_EXISTS,
        "icon_sprite_sheet.svg": $SVG_EXISTS,
        "typography_guide.pdf": $PDF_EXISTS
    }
}
EOF

echo "=== Export Complete ==="