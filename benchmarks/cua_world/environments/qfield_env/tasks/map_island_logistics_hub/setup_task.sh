#!/system/bin/sh
set -e
echo "=== Setting up task: map_island_logistics_hub ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField working directory for imported datasets
WORK_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
TARGET_GPKG="$WORK_DIR/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Ensure working directory exists
mkdir -p "$WORK_DIR"

# Reset the GeoPackage to a clean state from the immutable source
# This ensures no previous attempts pollute the verification
cp "$SOURCE_GPKG" "$TARGET_GPKG"
# Ensure it is writable
chmod 666 "$TARGET_GPKG"

# Record initial record count in field_observations
# We use sqlite3 which should be available in the Android env
if [ -f "$TARGET_GPKG" ]; then
    sqlite3 "$TARGET_GPKG" "SELECT count(*) FROM field_observations;" > /sdcard/initial_count.txt
else
    echo "0" > /sdcard/initial_count.txt
fi

echo "Initial count recorded: $(cat /sdcard/initial_count.txt)"

# Force stop QField to ensure clean start
am force-stop $PACKAGE
sleep 2

# Launch QField
# We launch it to the home screen. The agent must open the project.
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Attempt to dismiss "Release Notes" or "Welcome" dialogs if they appear
# Coordinates for standard 'OK' or 'Close' buttons on 1080x2400
input tap 540 2200 2>/dev/null || true
sleep 1

echo "=== Task setup complete ==="