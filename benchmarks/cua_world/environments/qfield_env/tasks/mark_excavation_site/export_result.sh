#!/system/bin/sh
# Export script for mark_excavation_site task.
# Saves the modified GeoPackage and final screenshot for verification.

echo "=== Exporting mark_excavation_site results ==="

WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
EXPORT_DIR="/sdcard/task_export"
mkdir -p "$EXPORT_DIR"

# Capture final screenshot
screencap -p "$EXPORT_DIR/task_final.png"

# Check if QField is still in foreground (app was running)
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "ch.opengis.qfield"; then
    APP_RUNNING="true"
fi

# Export the GeoPackage for verification
# We copy it to a standard location that copy_from_env can access reliably
if [ -f "$WORK_GPKG" ]; then
    cp "$WORK_GPKG" "$EXPORT_DIR/result.gpkg"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$WORK_GPKG" | awk '{print $4}')
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# Create a simple JSON metadata file
# Note: Android shell usually has limited JSON tools, so we write manually
cat > "$EXPORT_DIR/result_meta.json" <<EOF
{
    "app_running": $APP_RUNNING,
    "gpkg_exists": $GPKG_EXISTS,
    "gpkg_size": $GPKG_SIZE,
    "timestamp": "$(date +%s)"
}
EOF

echo "Export complete. Files ready in $EXPORT_DIR"
ls -l "$EXPORT_DIR"