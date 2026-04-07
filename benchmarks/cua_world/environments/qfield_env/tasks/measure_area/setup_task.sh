#!/system/bin/sh
# Setup script for measure_area task
# Runs inside Android emulator

echo "=== Setting up measure_area task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_DEST="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
TASK_DIR="/sdcard/tasks/measure_area"

# 1. Prepare Data
# Ensure we have a clean copy of the project
if [ -f "$GPKG_SRC" ]; then
    mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
    cp "$GPKG_SRC" "$GPKG_DEST"
    chmod 666 "$GPKG_DEST"
    echo "Project file prepared at $GPKG_DEST"
else
    echo "ERROR: Source GeoPackage not found at $GPKG_SRC"
    exit 1
fi

# 2. Record Initial State
# Save start time for anti-gaming checks
date +%s > /sdcard/task_start_time.txt

# 3. Launch Application
# Force stop to ensure clean start
am force-stop $PACKAGE
sleep 2

# Launch QField directly opening the project
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 5
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch failed, trying fallback..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    # Give extra time for map rendering
    sleep 10
fi

# 4. Capture Initial Screenshot
screencap -p /sdcard/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="