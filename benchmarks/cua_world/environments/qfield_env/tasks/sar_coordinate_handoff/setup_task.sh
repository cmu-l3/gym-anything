#!/bin/bash
set -e
echo "=== Setting up SAR Coordinate Handoff Task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# Target path in QField's private storage (where it reads/writes)
APP_DATA_DIR="/sdcard/Android/data/$PACKAGE/files/Imported Datasets"
GPKG_PATH="$APP_DATA_DIR/world_survey.gpkg"

# Target Coordinates for the task (East of Cairo)
CLUE_TEXT="SAR Target: Lat 30.10, Lon 31.50"

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Reset State
echo "Stopping QField..."
adb shell am force-stop $PACKAGE
sleep 2

# 2. Prepare Data
echo "Restoring clean GeoPackage..."
# Ensure directory exists
adb shell mkdir -p "$APP_DATA_DIR"
# Copy clean file from read-only mount
adb shell cp "$SOURCE_GPKG" "$GPKG_PATH"
# Fix permissions just in case
adb shell chmod 666 "$GPKG_PATH"

# 3. Inject Clue into Ottawa Feature
echo "Injecting clue into Ottawa feature..."
# Update the description of Ottawa to contain the coordinates
UPDATE_CMD="UPDATE world_capitals SET description = '$CLUE_TEXT' WHERE name = 'Ottawa';"
adb shell sqlite3 "$GPKG_PATH" "\"$UPDATE_CMD\""

# Verify injection
VERIFY_CMD="SELECT description FROM world_capitals WHERE name = 'Ottawa';"
RESULT=$(adb shell sqlite3 "$GPKG_PATH" "\"$VERIFY_CMD\"")

if [[ "$RESULT" == *"$CLUE_TEXT"* ]]; then
    echo "Injection successful."
else
    echo "ERROR: Failed to inject clue. Result: $RESULT"
    exit 1
fi

# 4. Launch QField
echo "Launching QField..."
# Launching via monkey to ensure it opens to the main activity/last state
adb shell monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
sleep 5

# 5. Capture Initial State
echo "Capturing initial state..."
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png

echo "=== Setup complete ==="