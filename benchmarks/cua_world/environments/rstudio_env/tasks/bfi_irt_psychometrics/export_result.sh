#!/bin/bash
echo "=== Exporting BFI IRT Psychometrics Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
OUT_DIR="/home/ga/RProjects/output"
FILE_REL="$OUT_DIR/bfi_reliability.csv"
FILE_PARAM="$OUT_DIR/bfi_grm_parameters.csv"
FILE_FIT="$OUT_DIR/bfi_item_fit.csv"
FILE_PLOT="$OUT_DIR/bfi_irt_plots.png"
SCRIPT_PATH="/home/ga/RProjects/bfi_irt_analysis.R"

# Function to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path")
        local size=$(stat -c %s "$path")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"new\": true, \"size\": $size, \"path\": \"$path\"}"
        else
            echo "{\"exists\": true, \"new\": false, \"size\": $size, \"path\": \"$path\"}"
        fi
    else
        echo "{\"exists\": false, \"new\": false, \"size\": 0, \"path\": \"$path\"}"
    fi
}

# Check all files
STAT_REL=$(check_file "$FILE_REL")
STAT_PARAM=$(check_file "$FILE_PARAM")
STAT_FIT=$(check_file "$FILE_FIT")
STAT_PLOT=$(check_file "$FILE_PLOT")

# Check script modification
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "reliability": $STAT_REL,
        "parameters": $STAT_PARAM,
        "fit": $STAT_FIT,
        "plot": $STAT_PLOT
    },
    "script_modified": $SCRIPT_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Prepare files for extraction by verifier (copy to /tmp for easier access if needed)
# We strictly rely on copy_from_env in the verifier, so we don't need to move them here
# unless they are in restricted directories. /home/ga is accessible.

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="