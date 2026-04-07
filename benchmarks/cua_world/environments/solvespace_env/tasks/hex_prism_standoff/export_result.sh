#!/bin/bash
echo "=== Exporting hex_prism_standoff task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing anything
take_screenshot /tmp/task_final.png

# Retrieve timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SLVS_PATH="/home/ga/Documents/SolveSpace/hex_standoff.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/hex_standoff.stl"

# Function to safely retrieve file metadata
get_file_info() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "{\"exists\": true, \"size\": $(stat -c%s "$path"), \"mtime\": $(stat -c%Y "$path")}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0}"
    fi
}

SLVS_INFO=$(get_file_info "$SLVS_PATH")
STL_INFO=$(get_file_info "$STL_PATH")

# Write results to JSON for the verifier script to read
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs": $SLVS_INFO,
    "stl": $STL_INFO
}
EOF

# Move JSON into place with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Task result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="