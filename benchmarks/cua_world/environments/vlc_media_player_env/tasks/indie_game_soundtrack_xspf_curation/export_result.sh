#!/bin/bash
set -e
echo "=== Exporting Indie Game Soundtrack XSPF Curation Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if the output directory exists
TRACKS_DIR="/home/ga/Desktop/OST_Distribution/tracks"
if [ -d "$TRACKS_DIR" ]; then
    DIR_EXISTS="true"
    # Count normal files (exclude symlinks)
    FILE_COUNT=$(find "$TRACKS_DIR" -maxdepth 1 -type f | wc -l)
    SYMLINK_COUNT=$(find "$TRACKS_DIR" -maxdepth 1 -type l | wc -l)
else
    DIR_EXISTS="false"
    FILE_COUNT=0
    SYMLINK_COUNT=0
fi

# Check XSPF playlist
XSPF_PATH="/home/ga/Desktop/OST_Distribution/soundtrack.xspf"
if [ -f "$XSPF_PATH" ]; then
    XSPF_EXISTS="true"
    # Copy to /tmp so verifier can easily read it
    cp "$XSPF_PATH" /tmp/soundtrack_export.xspf
    chmod 666 /tmp/soundtrack_export.xspf
    XSPF_MTIME=$(stat -c %Y "$XSPF_PATH" 2>/dev/null || echo "0")
    if [ "$XSPF_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    XSPF_EXISTS="false"
    CREATED_DURING_TASK="false"
fi

# Gather copied filenames to evaluate exact match
if [ "$DIR_EXISTS" = "true" ]; then
    COPIED_FILES=$(ls -1 "$TRACKS_DIR" | tr '\n' ',' | sed 's/,$//')
else
    COPIED_FILES=""
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dir_exists": $DIR_EXISTS,
    "file_count": $FILE_COUNT,
    "symlink_count": $SYMLINK_COUNT,
    "xspf_exists": $XSPF_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "copied_files": "$COPIED_FILES",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="