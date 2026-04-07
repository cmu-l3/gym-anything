#!/system/bin/sh
# Setup script for add_relay_midpoint task.
# Resets the GeoPackage and launches QField.

echo "=== Setting up add_relay_midpoint task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TARGET="$DATA_DIR/world_survey.gpkg"

# 1. Prepare Data
# Create a fresh, writable copy of the GeoPackage
echo "Resetting GeoPackage data..."
mkdir -p "$DATA_DIR"
cp "$GPKG_SOURCE" "$GPKG_TARGET"
chmod 666 "$GPKG_TARGET"

# 2. Record Initial State
# Record task start time (Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# Record initial number of observations using sqlite3 if available, 
# otherwise assume 8 (known from env description)
if [ -f "/system/bin/sqlite3" ]; then
    /system/bin/sqlite3 "$GPKG_TARGET" "SELECT COUNT(*) FROM field_observations;" > /sdcard/initial_count.txt
else
    echo "8" > /sdcard/initial_count.txt
fi

# 3. Launch Application
echo "Force stopping QField..."
am force-stop $PACKAGE
sleep 2

echo "Pressing Home..."
input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with world_survey.gpkg..."
# Use VIEW intent to open specific project directly
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_TARGET" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" > /dev/null 2>&1

# Wait for app to load
sleep 5
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "Intent launch failed, trying manual launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1
    sleep 10
else
    sleep 10
fi

# Ensure map is visible (dismiss any lingering dialogs if needed)
# QField remembers last view, but fresh GPKG usually resets view.
# We trust the agent to navigate.

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="