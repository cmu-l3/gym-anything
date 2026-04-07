#!/bin/bash
# Export script for stadium_display_content_formatting task
set -e

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Helper function to extract robust video metadata via ffprobe
probe_file() {
    local file=$1
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
        
        # Determine if file was created/modified after task started
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi

        # Use ffprobe to extract real metadata securely inside the container
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
        local width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
        local height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
        local audio_streams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l || echo "0")
        
        # Output as JSON string fragment
        echo "{\"exists\": true, \"created_during_task\": $created_during_task, \"size\": $size, \"duration\": ${duration:-0}, \"width\": ${width:-0}, \"height\": ${height:-0}, \"audio_streams\": $audio_streams}"
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0, \"duration\": 0, \"width\": 0, \"height\": 0, \"audio_streams\": 0}"
    fi
}

echo "Probing Jumbotron file..."
JUMBOTRON_JSON=$(probe_file "/home/ga/Videos/stadium_ready/jumbotron_ad.mp4")

echo "Probing Ribbon Board file..."
RIBBON_JSON=$(probe_file "/home/ga/Videos/stadium_ready/ribbon_board_ad.mp4")

# Read the manifest safely into a JSON escaped string to pass back
MANIFEST_PATH="/home/ga/Documents/deployment.json"
MANIFEST_EXISTS="false"
MANIFEST_CONTENT="{}"
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    # Read content, escape quotes and newlines for embedding inside the master JSON
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH" | jq -c '.' 2>/dev/null || echo "{}")
fi

# Build final results JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jumbotron": $JUMBOTRON_JSON,
    "ribbon": $RIBBON_JSON,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content": $MANIFEST_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location securely
rm -f /tmp/stadium_export.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/stadium_export.json 2>/dev/null
chmod 666 /tmp/stadium_export.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results recorded in /tmp/stadium_export.json"
cat /tmp/stadium_export.json
echo "=== Export complete ==="