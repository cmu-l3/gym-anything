#!/system/bin/sh
# Setup script for classify_island_capitals task

echo "=== Setting up classify_island_capitals task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="ch.opengis.qfield"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
# QField working directory for imported projects
# Note: Path may vary slightly by device/version, but this is standard for Android/QField
GPKG_DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_DEST="$GPKG_DEST_DIR/world_survey.gpkg"

# 1. Clean Slate: Force stop QField
echo "Stopping QField..."
am force-stop $PACKAGE
sleep 2

# 2. Prepare Data
echo "Preparing GeoPackage..."
mkdir -p "$GPKG_DEST_DIR"

# Copy fresh file
if [ -f "$GPKG_SOURCE" ]; then
    cp "$GPKG_SOURCE" "$GPKG_DEST"
    chmod 666 "$GPKG_DEST"
else
    echo "ERROR: Source GeoPackage not found at $GPKG_SOURCE"
    exit 1
fi

# 3. Reset target fields (Anti-Gaming / Clean State)
# We clear the description field for our target cities to ensure the agent does the work
if [ -f "/system/bin/sqlite3" ]; then
    echo "Resetting target city descriptions..."
    sqlite3 "$GPKG_DEST" "UPDATE world_capitals SET description = '' WHERE name IN ('Dublin', 'Tokyo', 'Antananarivo', 'Paris', 'Cairo', 'Brasilia');"
else
    echo "WARNING: sqlite3 not found, skipping data reset. Task relies on overwrite."
fi

# 4. Launch QField with the project
# Using VIEW intent to open the specific file directly
echo "Launching QField..."
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_DEST" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Wait for app to load
sleep 10

# 5. Capture Initial State
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="