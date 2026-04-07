#!/system/bin/sh
echo "=== Setting up Triangulate Coordinate Intersection Task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"

# Record task start timestamp for verification
date +%s > /sdcard/task_start_time.txt

# ensure destination directory exists
mkdir -p "$DEST_DIR"

# Copy fresh GeoPackage to ensure clean state and writable permissions
# We overwrite any existing file to remove previous task artifacts
cp "$SOURCE_GPKG" "$DEST_GPKG"
chmod 666 "$DEST_GPKG"

echo "GeoPackage prepared at: $DEST_GPKG"

# Force stop QField to ensure a fresh start
am force-stop "$PACKAGE"
sleep 2

# Go to Home Screen
input keyevent KEYCODE_HOME
sleep 2

# Launch QField
# We launch via the MAIN activity. The agent must navigate to open the file.
# This ensures they see the project selection screen.
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 10

# Dismiss any potential "Release Notes" or "Beta" dialogs that might appear on fresh install
# Tapping center/bottom area just in case
input tap 540 1800 2>/dev/null
sleep 1

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="