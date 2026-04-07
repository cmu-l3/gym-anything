#!/system/bin/sh
echo "=== Setting up locate_distress_beacons task ==="

PACKAGE="ch.opengis.qfield"
MASTER_GPKG="/sdcard/QFieldData/world_survey.gpkg"
WORKING_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
WORKING_GPKG="$WORKING_DIR/world_survey.gpkg"

# 1. Force stop QField to release file locks
am force-stop $PACKAGE
sleep 2

# 2. Ensure working directory exists
mkdir -p "$WORKING_DIR"

# 3. Overwrite with fresh GeoPackage data (Clean State)
# We copy from the read-only master mount to the app's writable directory
if [ -f "$MASTER_GPKG" ]; then
    cp "$MASTER_GPKG" "$WORKING_GPKG"
    chmod 666 "$WORKING_GPKG"
    echo "Restored fresh world_survey.gpkg"
else
    echo "ERROR: Master GeoPackage not found at $MASTER_GPKG"
    exit 1
fi

# 4. Record start time (using simple file touch as 'date +%s' might be limited in minimal android shell)
# We'll use the modification time of this marker file for basic checks
touch /sdcard/task_start_marker

# 5. Launch QField and open the project
echo "Launching QField..."
# Open specifically with VIEW intent to ensure project loads
am start -a android.intent.action.VIEW \
    -d "file://$WORKING_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# 6. Wait for app to load (simple sleep)
sleep 15

# 7. Dismiss any 'Welcome' or 'Beta' dialogs if they appear (tap center-bottom)
# Coordinates generic for 1080x2400
input tap 540 2000
sleep 1

echo "=== Task setup complete ==="