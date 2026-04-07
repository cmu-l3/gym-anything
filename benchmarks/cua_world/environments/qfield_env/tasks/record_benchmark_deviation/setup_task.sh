#!/system/bin/sh
# Setup script for record_benchmark_deviation task.
# Resets the GeoPackage and records the initial number of observations.

echo "=== Setting up record_benchmark_deviation task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# 1. Force stop QField to ensure clean start
am force-stop $PACKAGE
sleep 2

# 2. Create a fresh writable copy of the GeoPackage
# This ensures previous task data is wiped
echo "Creating fresh writable copy of GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"

# 3. Record initial observation count for verification
# We use the sqlite3 binary included in the Android image to query the GPKG
if [ -f "$GPKG_TASK" ]; then
    INITIAL_COUNT=$(sqlite3 "$GPKG_TASK" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
else
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /data/local/tmp/initial_count.txt
echo "Initial observation count: $INITIAL_COUNT"

# 4. Record start time
date +%s > /data/local/tmp/task_start_time.txt

# 5. Launch QField with the project
# We use the VIEW intent to open the specific project file immediately
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# 6. Wait for app to load (simple heuristic)
sleep 10

echo "=== Task setup complete ==="