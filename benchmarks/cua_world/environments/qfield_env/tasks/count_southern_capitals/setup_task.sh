#!/system/bin/sh
set -e
echo "=== Setting up count_southern_capitals task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
TASK_DIR="/sdcard/tasks/count_southern_capitals"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="$DATA_DIR/world_survey.gpkg"

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Clean up previous task artifacts
rm -f /sdcard/southern_hemisphere_capitals.txt
rm -f /sdcard/task_result.json

# Ensure the GeoPackage exists in the QField directory
mkdir -p "$DATA_DIR"
if [ ! -f "$GPKG_DEST" ]; then
    echo "Restoring world_survey.gpkg..."
    cp "$GPKG_SOURCE" "$GPKG_DEST"
else
    # overwrite to ensure clean state (no previous edits)
    cp "$GPKG_SOURCE" "$GPKG_DEST"
fi
chmod 666 "$GPKG_DEST"

# Force stop QField to ensure a fresh start
am force-stop "$PACKAGE"
sleep 2

# Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="
echo "Target GeoPackage: $GPKG_DEST"
echo "Output required: /sdcard/southern_hemisphere_capitals.txt"