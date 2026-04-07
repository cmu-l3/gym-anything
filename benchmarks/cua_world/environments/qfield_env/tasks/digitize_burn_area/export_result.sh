#!/system/bin/sh
set -e
echo "=== Exporting digitize_burn_area results ==="

GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# Get task start time
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check file modification time
FILE_MODIFIED="false"
if [ -f "$GPKG_PATH" ]; then
    # Android ls -l usually shows date/time. stat might not be available or formatted simply.
    # We'll rely on the verifier to check the file content changes, 
    # but here we check existence.
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$GPKG_PATH" | awk '{print $4}' 2>/dev/null || echo "0")
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# We don't run complex verification logic on Android (limited shell).
# We export the GeoPackage and let the host Python verifier do the work.
# We just create a metadata JSON here.

cat > "$RESULT_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gpkg_exists": $GPKG_EXISTS,
    "gpkg_path_android": "$GPKG_PATH",
    "gpkg_size": $GPKG_SIZE,
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# Ensure permissions for adb pull
chmod 666 "$GPKG_PATH" 2>/dev/null || true
chmod 666 "$RESULT_JSON" 2>/dev/null || true
chmod 666 "$FINAL_SCREENSHOT" 2>/dev/null || true

echo "Export complete. Files ready for pull."