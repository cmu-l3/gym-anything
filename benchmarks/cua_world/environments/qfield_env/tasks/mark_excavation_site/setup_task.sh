#!/system/bin/sh
# Setup script for mark_excavation_site task.
# Prepares a writable GeoPackage and launches QField.

echo "=== Setting up mark_excavation_site task ==="

PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Record start timestamp
date +%s > /sdcard/task_start_time.txt

# Force stop QField to ensure clean state
am force-stop $PACKAGE
sleep 2

# Create a fresh writable copy of the GeoPackage
# We use the app's private directory to ensure it's writable by QField
echo "Preparing writable GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$SOURCE_GPKG" "$WORK_GPKG"
# Ensure writable permissions (simulated for emulator environment)
chmod 666 "$WORK_GPKG"

# Ensure we are at Home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch QField directly opening the project file via Intent
# This bypasses the need to navigate the file browser manually
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file://$WORK_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to launch and load
sleep 5
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch failed, trying fallback monkey launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    # Give extra time for the project to parse and load the map
    sleep 10
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="
echo "Target GeoPackage: $WORK_GPKG"