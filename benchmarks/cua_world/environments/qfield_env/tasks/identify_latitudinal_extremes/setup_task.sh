#!/system/bin/sh
# Setup script for identify_latitudinal_extremes
# Resets the project data and launches QField

echo "=== Setting up identify_latitudinal_extremes task ==="

PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
TASK_DIR="/sdcard/tasks/identify_latitudinal_extremes"

# 1. Force stop QField to ensure clean start and release DB locks
am force-stop $PACKAGE
sleep 2

# 2. Reset the GeoPackage to ensure no previous observations exist
# We copy from the read-only source to the app's private storage
echo "Resetting GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$SOURCE_GPKG" "$WORK_GPKG"
chmod 666 "$WORK_GPKG"

# 3. Record start time for anti-gaming checks
date +%s > /sdcard/task_start_time.txt

# 4. Clean up any previous results
rm -f /sdcard/task_result.gpkg 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

# 5. Launch QField directly into the project
# Using the VIEW intent forces QField to open this specific file
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$WORK_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# 6. Wait for app to load (basic heuristics)
sleep 10
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "Intent failed, retrying launch via Monkey..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== Setup complete ==="