#!/bin/bash
# export_result.sh - Post-task export for web_image_optimization
set -e

echo "=== Exporting Task Results ==="

# 1. basic setup
OUTPUT_DIR="/home/ga/Documents/WebReady"
OUTPUT_FILE="$OUTPUT_DIR/hero_optimized.webp"
SOURCE_FILE="/home/ga/Pictures/RawAssets/marketing_hero_source.png"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze Output File
EXISTS="false"
WIDTH=0
HEIGHT=0
FORMAT="unknown"
SIZE_BYTES=0
CREATED_AFTER_START="false"
SOURCE_SIZE=$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        CREATED_AFTER_START="true"
    fi

    # Use ImageMagick to get details
    # %w=width, %h=height, %m=magick_format
    if command -v identify >/dev/null 2>&1; then
        IMG_INFO=$(identify -format "%w|%h|%m" "$OUTPUT_FILE" 2>/dev/null || echo "0|0|unknown")
        WIDTH=$(echo "$IMG_INFO" | cut -d'|' -f1)
        HEIGHT=$(echo "$IMG_INFO" | cut -d'|' -f2)
        FORMAT=$(echo "$IMG_INFO" | cut -d'|' -f3)
    fi
fi

# 4. Check Browser History for Tool Usage
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
VISITED_TOOL="false"
if [ -f "$HISTORY_DB" ]; then
    # Copy DB to avoid locks
    cp "$HISTORY_DB" /tmp/history_check.db
    # Check for squoosh.app
    VISIT_COUNT=$(sqlite3 /tmp/history_check.db "SELECT count(*) FROM urls WHERE url LIKE '%squoosh.app%';" 2>/dev/null || echo "0")
    if [ "$VISIT_COUNT" -gt "0" ]; then
        VISITED_TOOL="true"
    fi
    rm -f /tmp/history_check.db
fi

# 5. Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "output_exists": $EXISTS,
    "output_path": "$OUTPUT_FILE",
    "width": $WIDTH,
    "height": $HEIGHT,
    "format": "$FORMAT",
    "size_bytes": $SIZE_BYTES,
    "source_size_bytes": $SOURCE_SIZE,
    "created_after_start": $CREATED_AFTER_START,
    "visited_tool": $VISITED_TOOL,
    "task_start_ts": $TASK_START_TIME,
    "export_ts": $CURRENT_TIME
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json