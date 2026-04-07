#!/system/bin/sh
# Setup script for map_seismic_antipode task
# Resets the GeoPackage and launches QField

echo "=== Setting up map_seismic_antipode task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
TIMESTAMP_FILE="/sdcard/task_start_time.txt"

# 1. Record Start Time
date +%s > "$TIMESTAMP_FILE"

# 2. Reset Data
# Force stop QField to release file locks
am force-stop $PACKAGE
sleep 2

# Create a fresh writable copy of the GeoPackage
echo "Resetting GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
# Ensure it's writable
chmod 666 "$GPKG_TASK"

# 3. Launch QField
# We launch via intent to ensure the project is loaded
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_TASK" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 15

# 4. Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="