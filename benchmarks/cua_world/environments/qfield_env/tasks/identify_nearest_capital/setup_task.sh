#!/system/bin/sh
set -e
echo "=== Setting up identify_nearest_capital task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="$DATA_DIR/world_survey.gpkg"

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Create directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Copy a fresh GeoPackage to ensure clean state and no previous edits
# We copy from the read-only mount to the app's writable directory
echo "Restoring clean GeoPackage..."
cp "$GPKG_SOURCE" "$GPKG_DEST"
chmod 666 "$GPKG_DEST"

# Record initial feature count for anti-gaming verification
# We use sqlite3 which is available in the Android env
INITIAL_COUNT=$(sqlite3 "$GPKG_DEST" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /sdcard/initial_observation_count.txt
echo "Initial observation count: $INITIAL_COUNT"

# Snapshot existing feature IDs to distinguish new features later
sqlite3 "$GPKG_DEST" "SELECT fid FROM field_observations;" 2>/dev/null > /sdcard/initial_observation_ids.txt || true

# Force stop QField to ensure a clean cold start
am force-stop $PACKAGE
sleep 2

# Press Home to clear screen
input keyevent KEYCODE_HOME
sleep 1

# Launch QField directly opening the project file via Intent
# This saves the agent from navigating the file menu
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 10

# Dismiss any potential "Release Notes" or "Beta" dialogs that might appear on fresh install
# We tap Back once just in case
input keyevent KEYCODE_BACK 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png
echo "Initial screenshot captured"

echo "=== Task setup complete ==="
echo "Target coordinates: 58.0 N, 19.5 E"