#!/system/bin/sh
# Export script for multi_site_survey task
# Runs inside Android environment

echo "=== Exporting multi_site_survey results ==="

PACKAGE="ch.opengis.qfield"
GPKG_WORK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Close App to flush database WAL (Write-Ahead Log)
echo "Closing QField..."
am force-stop $PACKAGE
sleep 2

# 2. Check file status
GPKG_EXISTS="false"
GPKG_SIZE="0"
if [ -f "$GPKG_WORK" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$GPKG_WORK" | awk '{print $5}')
fi

# 3. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 4. Take Final Screenshot
screencap -p /sdcard/task_final.png

# 5. Generate JSON Result
# Note: Simple JSON generation using shell
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$GPKG_WORK\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON generated at $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export complete ==="