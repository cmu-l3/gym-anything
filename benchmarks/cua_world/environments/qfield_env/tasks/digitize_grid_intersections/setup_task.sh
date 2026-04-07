#!/system/bin/sh
echo "=== Setting up Digitize Grid Intersections task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField opens "Imported Datasets" by default when clicking "Open Local Project"
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"

# 1. Clean up previous runs
rm -f "$DEST_GPKG"
rm -f "$DEST_GPKG-shm"
rm -f "$DEST_GPKG-wal"
rm -f "/sdcard/task_result.json"

# 2. Prepare writable GeoPackage
# We copy it to the app's private storage so it's writable and visible in QField
mkdir -p "$DEST_DIR"
cp "$SOURCE_GPKG" "$DEST_GPKG"
chmod 666 "$DEST_GPKG"

echo "GeoPackage prepared at: $DEST_GPKG"

# 3. Record task start time
date +%s > /sdcard/task_start_time.txt

# 4. Get initial feature count (to detect additions)
# Note: Android sqlite3 might not have spatialite loaded, but we can count rows
INITIAL_COUNT=$(sqlite3 "$DEST_GPKG" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /sdcard/initial_count.txt

# 5. Launch QField
# Force stop to ensure clean start
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch App
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for load
sleep 5

echo "=== Task setup complete ==="