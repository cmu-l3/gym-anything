#!/system/bin/sh
echo "=== Exporting log_feature_coordinates results ==="

# Define paths
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"
TIMESTAMP_FILE="/sdcard/task_start_time.txt"

# Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# Get timestamps
TASK_START=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_MOD_TIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")

# Check if GeoPackage exists
GPKG_EXISTS="false"
if [ -f "$GPKG_PATH" ]; then
    GPKG_EXISTS="true"
fi

# Create a temporary copy of the GPKG for the verifier to pull
# (Using a consistent name in /sdcard makes it easier for copy_from_env)
cp "$GPKG_PATH" /sdcard/world_survey_result.gpkg
chmod 666 /sdcard/world_survey_result.gpkg

# Create JSON result
# We construct the JSON manually using echo since jq might not be available on Android
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_mod_time\": $FILE_MOD_TIME," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"/sdcard/world_survey_result.gpkg\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"