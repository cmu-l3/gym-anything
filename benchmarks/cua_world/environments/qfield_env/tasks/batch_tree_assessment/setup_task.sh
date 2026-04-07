#!/system/bin/sh
set -e
echo "=== Setting up batch_tree_assessment task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="$DATA_DIR/world_survey.gpkg"
TASK_START_FILE="/sdcard/task_start_time.txt"
INITIAL_COUNT_FILE="/sdcard/initial_observation_count.txt"

# 1. Record task start time
date +%s > "$TASK_START_FILE"

# 2. Prepare Data
# Ensure the directory exists
mkdir -p "$DATA_DIR"

# Copy a FRESH copy of the GeoPackage to ensure clean state
# We use the one from Imported Datasets as it's the standard writeable location in QField
cp "$GPKG_SOURCE" "$GPKG_DEST"
chmod 666 "$GPKG_DEST"

# 3. Record Initial State
# Use sqlite3 to count existing records if available, otherwise default to known ground truth (8)
if command -v sqlite3 >/dev/null 2>&1; then
    INITIAL_COUNT=$(sqlite3 "$GPKG_DEST" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null)
else
    INITIAL_COUNT="8"
fi
echo "$INITIAL_COUNT" > "$INITIAL_COUNT_FILE"
echo "Initial observation count: $INITIAL_COUNT"

# 4. Launch Application
# Force stop first to ensure full reload
am force-stop $PACKAGE
sleep 2

# Press Home to ensure clean back stack
input keyevent KEYCODE_HOME
sleep 1

# Launch QField directly opening the project via Intent
# This bypasses the project selection screen for reliability
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 15

# Dismiss any potential "Missing project" or tutorial dialogs via generic taps if needed
# (The environment setup script handles the main tutorials, this is a safety net)
# Tap roughly center-bottom to dismiss generic info dialogs
input tap 540 2000 2>/dev/null || true

# 5. Capture Initial Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="