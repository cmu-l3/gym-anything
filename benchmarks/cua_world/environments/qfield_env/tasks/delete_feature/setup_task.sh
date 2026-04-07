#!/system/bin/sh
# Setup script for delete_feature task.
# Prepares a writable GeoPackage and records initial state.

echo "=== Setting up delete_feature task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
WORKING_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
WORKING_GPKG="$WORKING_DIR/world_survey.gpkg"
TASK_INFO_DIR="/data/local/tmp"

# Create working directory if it doesn't exist
mkdir -p "$WORKING_DIR"

# 1. Prepare Data
# Copy a fresh, writable GeoPackage to the working directory
echo "Restoring clean GeoPackage..."
cp "$SOURCE_GPKG" "$WORKING_GPKG"
chmod 666 "$WORKING_GPKG"

# 2. Record Task Start Time (Anti-gaming)
date +%s > "$TASK_INFO_DIR/task_start_time.txt"

# 3. Launch QField
# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to start from a neutral place
input keyevent KEYCODE_HOME
sleep 1

# Launch QField via VIEW intent to open the project directly
# This ensures the agent starts with the map loaded, ready to find the feature
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$WORKING_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 5
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch failed, trying manual launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
else
    sleep 10
fi

# 4. Initial Screenshot
screencap -p /data/local/tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: Delete 'Tokyo' from $WORKING_GPKG"