#!/system/bin/sh
# Setup script for plan_capital_relocation task
# Runs inside Android emulator

echo "=== Setting up plan_capital_relocation task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
DEST_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files"

# 1. timestamp start
date +%s > /sdcard/task_start_time.txt

# 2. Prepare Data
# Create a fresh, writable copy of the GeoPackage
# This ensures we don't have artifacts from previous runs
mkdir -p "$DEST_DIR"
cp "$SOURCE_GPKG" "$DEST_GPKG"
chmod 666 "$DEST_GPKG"

if [ -f "$DEST_GPKG" ]; then
    echo "GeoPackage prepared successfully."
else
    echo "ERROR: Failed to copy GeoPackage."
    exit 1
fi

# 3. Clean App State
# Force stop to ensure a fresh launch
am force-stop $PACKAGE
sleep 2

# Press Home to start from a neutral background
input keyevent KEYCODE_HOME
sleep 1

# 4. Launch QField directly into the project
# Using the VIEW intent with file URI often bypasses the project picker
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$DEST_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 5

# Check if launch succeeded (if not, retry via Launcher)
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "Intent launch didn't focus, retrying via Launcher..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
fi

# Wait for map to render
sleep 10

# 5. Capture Initial Evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="