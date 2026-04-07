#!/bin/bash
echo "=== Exporting SEM CFA Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/sem_analysis.R"

# Function to get file info
get_file_info() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path")
        local size=$(stat -c %s "$path")
        local is_new="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
        echo "{\"exists\": true, \"is_new\": $is_new, \"size\": $size, \"path\": \"$path\"}"
    else
        echo "{\"exists\": false, \"is_new\": false, \"size\": 0, \"path\": \"$path\"}"
    fi
}

# Collect info for all expected files
FIT_STATS=$(get_file_info "$OUTPUT_DIR/cfa_fit_statistics.csv")
LOADINGS=$(get_file_info "$OUTPUT_DIR/cfa_factor_loadings.csv")
INVARIANCE=$(get_file_info "$OUTPUT_DIR/measurement_invariance.csv")
DIAGRAM=$(get_file_info "$OUTPUT_DIR/cfa_path_diagram.png")
SCRIPT=$(get_file_info "$SCRIPT_PATH")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "files": {
        "fit_stats": $FIT_STATS,
        "loadings": $LOADINGS,
        "invariance": $INVARIANCE,
        "diagram": $DIAGRAM,
        "script": $SCRIPT
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result summary saved to /tmp/task_result.json"
echo "=== Export Complete ==="