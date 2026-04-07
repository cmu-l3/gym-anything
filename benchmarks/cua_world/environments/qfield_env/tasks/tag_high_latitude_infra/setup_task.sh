#!/system/bin/sh
# Setup for tag_high_latitude_infra
# Prepares QField with the world_survey project ready for editing.

echo "=== Setting up Tag High-Latitude Infrastructure task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField Import folder structure
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# 1. Clean up previous run artifacts
rm -f "$DEST_GPKG" 2>/dev/null
rm -f "$DEST_GPKG-wal" 2>/dev/null
rm -f "$DEST_GPKG-shm" 2>/dev/null

# 2. Stage the GeoPackage data
# We copy it to the app's private storage so it appears in "Imported Projects"
# and is writable.
mkdir -p "$DEST_DIR"
cp "$SOURCE_GPKG" "$DEST_GPKG"
# Ensure it's writable
chmod 666 "$DEST_GPKG"

echo "GeoPackage staged at: $DEST_GPKG"

# 3. Force stop QField to ensure clean start
am force-stop "$PACKAGE"
sleep 2

# 4. Launch QField directly into the project if possible, or Home
# Using VIEW intent with correct MIME type usually opens the project
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$DEST_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 10

# 5. Dismiss any "Missing Project" or "Update" dialogs if they appear
# (Tap center/bottom-right generic locations just in case)
input tap 540 1200 2>/dev/null || true

# 6. Capture initial state screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="