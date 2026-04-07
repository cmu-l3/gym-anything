#!/system/bin/sh
# Setup script for dispatch_nearest_hub task.
# Prepares the QField environment with a writable GeoPackage.

echo "=== Setting up dispatch_nearest_hub task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Prepare Data
# Create a fresh, writable copy of the GeoPackage.
# We copy it to the app's private storage so it appears in "QField files directory"
# and is writable by the app.
echo "Preparing writable GeoPackage..."
mkdir -p "$DEST_DIR"
cp "$SOURCE_GPKG" "$DEST_GPKG"

# Ensure permissions are correct (readable/writable by everyone/app)
chmod 666 "$DEST_GPKG"

# 3. Clean State
# Force stop QField to ensure no locks or stale state
echo "Stopping QField..."
am force-stop $PACKAGE
sleep 2

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# 4. Launch QField
# We launch QField directly with the VIEW intent for the project.
# This opens the project immediately, saving the agent from navigating the file menu.
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$DEST_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for load
sleep 5

# Check if launch succeeded, if not retry via Launcher
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch might have failed, trying standard launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
else
    echo "QField launched successfully."
    sleep 10
fi

# 5. Initial Screenshot
# (Optional: In this environment, the framework usually handles step capture, 
# but we can take one for debug if needed, though 'scrot' isn't on Android.
# We rely on the framework's observation stream.)

echo "=== Setup Complete ==="
echo "Target Coordinates: 9.0, -79.5"
echo "Project: $DEST_GPKG"