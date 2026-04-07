#!/system/bin/sh
set -e
echo "=== Setting up map_hazard_offset task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
# The working copy used by QField
GPKG_WORK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
# The clean source copy
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# 1. Force stop QField to ensure we can replace files and start clean
am force-stop $PACKAGE
sleep 2

# 2. Reset the GeoPackage to a clean state
echo "Resetting GeoPackage..."
# Ensure directory exists
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files/
# Copy fresh file
cp "$GPKG_SRC" "$GPKG_WORK"
# Ensure it's writable
chmod 666 "$GPKG_WORK"

# 3. Record initial feature count (for anti-gaming)
# We use sqlite3 if available, otherwise we rely on file mod time in export
if command -v sqlite3 >/dev/null 2>&1; then
    INITIAL_COUNT=$(sqlite3 "$GPKG_WORK" "SELECT count(*) FROM field_observations;" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /sdcard/initial_feature_count.txt
    echo "Initial feature count: $INITIAL_COUNT"
else
    echo "0" > /sdcard/initial_feature_count.txt
    echo "sqlite3 not found, using baseline 0"
fi

# 4. Launch QField directly into the project
# This saves the agent from navigating the file menu, focusing them on the map task
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_WORK" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# 5. Wait for app to load
sleep 10

# 6. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="