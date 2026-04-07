#!/system/bin/sh
set -e
echo "=== Setting up deploy_coastal_flood_sensors task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# The working copy that QField uses
WORK_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
WORK_GPKG="$WORK_DIR/world_survey.gpkg"
IMPORTED_GPKG="$WORK_DIR/Imported Datasets/world_survey.gpkg"

# 1. Force stop QField to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Prepare the Data
# We need a writable copy in the app's private storage
echo "Resetting GeoPackage..."
mkdir -p "$WORK_DIR"
mkdir -p "$WORK_DIR/Imported Datasets"

# Copy fresh source to working locations
cp "$SOURCE_GPKG" "$WORK_GPKG"
cp "$SOURCE_GPKG" "$IMPORTED_GPKG"

# Ensure permissions are correct
chmod 666 "$WORK_GPKG"
chmod 666 "$IMPORTED_GPKG"

# 3. Clean up any pre-existing sensor points (Anti-gaming)
# If sqlite3 is available in the env, we clean the table. 
# If not, the fresh copy above handles it (assuming source is clean).
if command -v sqlite3 >/dev/null; then
    echo "Cleaning field_observations table..."
    sqlite3 "$IMPORTED_GPKG" "DELETE FROM field_observations WHERE name LIKE 'Sensor_%';" 2>/dev/null || true
    sqlite3 "$WORK_GPKG" "DELETE FROM field_observations WHERE name LIKE 'Sensor_%';" 2>/dev/null || true
fi

# 4. Launch QField
# We launch into the Imported Dataset version to be safe, as that's the standard import path
echo "Launching QField..."
input keyevent KEYCODE_HOME
sleep 1

am start -a android.intent.action.VIEW \
    -d "file://$IMPORTED_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 10

# Capture initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="