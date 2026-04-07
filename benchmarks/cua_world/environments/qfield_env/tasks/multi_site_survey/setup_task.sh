#!/system/bin/sh
# Setup script for multi_site_survey task
# Runs inside Android environment

echo "=== Setting up multi_site_survey task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_WORK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
TASK_DIR="/sdcard/tasks/multi_site_survey"

# 1. Prepare Data
# Create a fresh, writable copy of the GeoPackage
# We copy from the read-only source mount to the app's private storage
echo "Resetting GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_WORK"
chmod 666 "$GPKG_WORK"

# Record start timestamp for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Launch QField
# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to start from a neutral place
input keyevent KEYCODE_HOME
sleep 1

# Launch QField with the project directly via Intent
# This opens the app and loads the project
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_WORK" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" > /dev/null 2>&1

# Wait for load (intent launch can take a moment)
sleep 10

# 3. Dismiss potential "Missing Project" or tutorial dialogs
# Tap center-ish just in case (safe interaction)
input tap 540 1200
sleep 1

echo "=== Setup complete ==="