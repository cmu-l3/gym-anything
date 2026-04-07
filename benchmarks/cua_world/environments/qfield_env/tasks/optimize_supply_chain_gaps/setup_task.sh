#!/system/bin/sh
set -e
echo "=== Setting up optimize_supply_chain_gaps ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField working directory for Imported Datasets
WORK_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
TARGET_GPKG="$WORK_DIR/world_survey.gpkg"

# 1. Clean up previous state
am force-stop $PACKAGE
sleep 2

# 2. Prepare Data
# Ensure the working directory exists
mkdir -p "$WORK_DIR"

# Copy a fresh GeoPackage to ensure no artifacts from previous runs
# We use a fresh copy every time so the agent starts clean
cp "$SOURCE_GPKG" "$TARGET_GPKG"
chmod 666 "$TARGET_GPKG"

if [ ! -f "$TARGET_GPKG" ]; then
    echo "ERROR: Failed to prepare GeoPackage at $TARGET_GPKG"
    exit 1
fi

# 3. Record Start Time and Initial State
date +%s > /sdcard/task_start_time.txt
# Get initial size/timestamp of the GPKG for comparison later
ls -l "$TARGET_GPKG" > /sdcard/initial_gpkg_state.txt

# 4. Launch QField directly into the project
# Using the VIEW intent forces QField to open this specific file
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$TARGET_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# 5. Wait for app to load
sleep 10

# 6. Capture initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="
echo "Project loaded: $TARGET_GPKG"