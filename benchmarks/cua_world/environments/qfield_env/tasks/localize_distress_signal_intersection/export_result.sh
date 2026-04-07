#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Define paths
TARGET_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
EXPORT_GPKG="/sdcard/task_result.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Export GeoPackage for Verification
# We copy it to a standard location that the verifier (running on host) can pull
if [ -f "$TARGET_GPKG" ]; then
    cp "$TARGET_GPKG" "$EXPORT_GPKG"
    chmod 644 "$EXPORT_GPKG"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$TARGET_GPKG" | awk '{print $5}')
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# 3. Get Task Timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create Metadata JSON
# Note: Simple JSON construction using echo
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$EXPORT_GPKG\"," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"