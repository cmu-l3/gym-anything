#!/system/bin/sh
echo "=== Setting up define_service_bounds task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField working directory for projects
PROJECT_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
TARGET_GPKG="$PROJECT_DIR/world_survey.gpkg"

# 1. Setup Data
echo "Preparing GeoPackage..."
mkdir -p "$PROJECT_DIR"

# Clean up any previous run
rm -f "$TARGET_GPKG"
rm -f "$TARGET_GPKG-wal"
rm -f "$TARGET_GPKG-shm"

# Copy fresh GeoPackage
# We use the source from /sdcard/QFieldData which is mounted RO usually, or safe source
cp "$SOURCE_GPKG" "$TARGET_GPKG"
chmod 666 "$TARGET_GPKG"

# Record start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# 2. Reset Application State
echo "Force stopping QField..."
am force-stop $PACKAGE
sleep 2

# Press Home to clear view
input keyevent KEYCODE_HOME
sleep 1

# 3. Launch QField
# We launch via intent to open the specific project immediately, 
# ensuring the agent starts in the right place.
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$TARGET_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 5
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch might have failed, trying Monkey..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
else
    # Allow extra time for layer loading
    sleep 10
fi

# Dismiss any potential 'Missing Project' or 'Errors' dialogs if they appear by pressing Back/Escape
# (Optional safety measure)
# input keyevent KEYCODE_BACK

echo "=== Task setup complete ==="