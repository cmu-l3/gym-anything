#!/bin/bash
echo "=== Exporting wildlife_trapcam_spatial_temporal_extraction results ==="

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || DISPLAY=:1 import -window root "$output_file" 2>/dev/null || true
}

# Record final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
A_PATH="/home/ga/Videos/processed_events/event_A_slow.mp4"
B_PATH="/home/ga/Videos/processed_events/event_B_slow.mp4"
JSON_PATH="/home/ga/Documents/processing_log.json"

# Helper to safely extract video info using ffprobe
get_vid_info() {
    local file=$1
    if [ -f "$file" ]; then
        local dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
        local res=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file" 2>/dev/null | tr -d '\n' || echo "0x0")
        echo "{\"exists\": true, \"duration\": $dur, \"resolution\": \"$res\"}"
    else
        echo "{\"exists\": false, \"duration\": 0, \"resolution\": \"0x0\"}"
    fi
}

# Collect Video Metadata
A_INFO=$(get_vid_info "$A_PATH")
B_INFO=$(get_vid_info "$B_PATH")

# Collect Modification Times (Anti-gaming)
A_MTIME=$(stat -c %Y "$A_PATH" 2>/dev/null || echo "0")
B_MTIME=$(stat -c %Y "$B_PATH" 2>/dev/null || echo "0")
JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")

# Make JSON manifest available to the verifier
cp "$JSON_PATH" /tmp/processing_log.json 2>/dev/null || true
chmod 666 /tmp/processing_log.json 2>/dev/null || true

# Assemble final result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "event_a": $A_INFO,
    "event_b": $B_INFO,
    "event_a_mtime": $A_MTIME,
    "event_b_mtime": $B_MTIME,
    "json_mtime": $JSON_MTIME
}
EOF

# Move to final location safely
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="