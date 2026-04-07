#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target files
SLVS_FILE="/home/ga/Documents/SolveSpace/production/base_v2.slvs"
STEP_FILE="/home/ga/Documents/SolveSpace/production/base_v2.step"
STL_FILE="/home/ga/Documents/SolveSpace/production/base_v2.stl"

# Function to safely stat a file
get_file_stat() {
    local file=$1
    if [ -f "$file" ]; then
        local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Check STEP header validity
STEP_VALID="false"
if [ -f "$STEP_FILE" ]; then
    if head -n 10 "$STEP_FILE" | grep -q "ISO-10303-21"; then
        STEP_VALID="true"
    fi
fi

# Check STL validity (either starts with 'solid' for ASCII or size > 84 for binary)
STL_VALID="false"
if [ -f "$STL_FILE" ]; then
    STL_SIZE=$(stat -c %s "$STL_FILE")
    if [ "$STL_SIZE" -gt 84 ]; then
        if head -n 1 "$STL_FILE" | grep -qi "^solid"; then
            STL_VALID="true" # ASCII
        else
            STL_VALID="true" # Binary
        fi
    fi
fi

# Build JSON strings
SLVS_JSON=$(get_file_stat "$SLVS_FILE")
STEP_JSON=$(get_file_stat "$STEP_FILE")
STL_JSON=$(get_file_stat "$STL_FILE")

# Check if app is running
APP_RUNNING="false"
if pgrep -f "solvespace" > /dev/null; then
    APP_RUNNING="true"
fi

# Create export JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "slvs": $SLVS_JSON,
    "step": $STEP_JSON,
    "stl": $STL_JSON,
    "step_header_valid": $STEP_VALID,
    "stl_header_valid": $STL_VALID
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="