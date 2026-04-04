#!/bin/bash
set -e
echo "=== Exporting compute_stage_area_curve results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather task metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/Documents/hec_ras_results"

# 3. Check output files
CSV_PATH="$RESULTS_DIR/stage_area_curve.csv"
INFO_PATH="$RESULTS_DIR/cross_section_info.txt"
PLOT_PATH="$RESULTS_DIR/stage_area_plot.png"

check_file() {
    local path="$1"
    local name="$2"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "\"${name}_exists\": true,"
        echo "\"${name}_created_during_task\": $created_during,"
        echo "\"${name}_size_bytes\": $size,"
        echo "\"${name}_path\": \"$path\","
    else
        echo "\"${name}_exists\": false,"
        echo "\"${name}_created_during_task\": false,"
        echo "\"${name}_size_bytes\": 0,"
        echo "\"${name}_path\": \"\","
    fi
}

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "\"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "\"task_end\": $TASK_END," >> "$TEMP_JSON"
check_file "$CSV_PATH" "csv" >> "$TEMP_JSON"
check_file "$INFO_PATH" "info" >> "$TEMP_JSON"
check_file "$PLOT_PATH" "plot" >> "$TEMP_JSON"
echo "\"screenshot_path\": \"/tmp/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# 5. Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="