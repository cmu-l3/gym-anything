#!/system/bin/sh
# Export script for log_eu_logistics_distances task
# Captures final state and metadata

echo "=== Exporting results ==="

PACKAGE="ch.opengis.qfield"
GPKG_TARGET="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result_meta.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Check if App is Running
if pidof ch.opengis.qfield > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Get File Statistics
if [ -f "$GPKG_TARGET" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$GPKG_TARGET")
    FILE_MTIME=$(stat -c %Y "$GPKG_TARGET")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
fi

# 4. Create Metadata JSON
# We write this to a file so the python verifier can read simple stats
# The python verifier will also pull the full .gpkg file to analyze content
echo "{" > "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"gpkg_mtime\": $FILE_MTIME" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Ensure permissions for adb pull
chmod 666 "$GPKG_TARGET"
chmod 666 "$RESULT_JSON"
chmod 666 "$FINAL_SCREENSHOT"

echo "=== Export complete ==="