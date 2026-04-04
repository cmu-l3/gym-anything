#!/system/bin/sh
# Export script for rank_antifungal_safety_with_axitinib task.

echo "=== Exporting results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Check output file
OUTPUT_FILE="/sdcard/antifungal_ranking.txt"
OUTPUT_EXISTS="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | tr '\n' '\\n')
fi

# Take final screenshot
screencap -p /sdcard/task_final.png

# Create result JSON
# Note: Android shell (mksh) often lacks advanced JSON tools, so we construct manually
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result saved to /sdcard/task_result.json"