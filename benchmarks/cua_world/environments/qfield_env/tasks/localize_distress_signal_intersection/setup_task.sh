#!/system/bin/sh
set -e
echo "=== Setting up Localize Distress Signal task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
TARGET_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
TARGET_GPKG="$TARGET_DIR/world_survey.gpkg"

# 1. Record Start Time
date +%s > /sdcard/task_start_time.txt

# 2. Prepare Clean Data
# We overwrite the target GeoPackage to ensure no stale data/edits exist.
echo "Resetting GeoPackage data..."
mkdir -p "$TARGET_DIR"
cp "$SOURCE_GPKG" "$TARGET_GPKG"
chmod 666 "$TARGET_GPKG"

# 3. Ensure QField is clean (force stop)
echo "Stopping QField..."
am force-stop $PACKAGE
sleep 2

# 4. Launch QField with the Project
# Using VIEW intent to open the specific project directly
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$TARGET_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# 5. Wait for App Load
sleep 10

# 6. Take Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="