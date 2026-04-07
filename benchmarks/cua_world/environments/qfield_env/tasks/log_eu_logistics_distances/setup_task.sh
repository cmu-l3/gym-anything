#!/system/bin/sh
# Setup script for log_eu_logistics_distances task
# Resets the GeoPackage and launches QField

echo "=== Setting up log_eu_logistics_distances task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TARGET="$DATA_DIR/world_survey.gpkg"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Record Start Time
date +%s > "$START_TIME_FILE"

# 2. Reset GeoPackage to ensure clean state
# Create directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Force stop QField to release file locks
am force-stop $PACKAGE
sleep 2

# Copy fresh GeoPackage
echo "Resetting GeoPackage..."
cp "$GPKG_SOURCE" "$GPKG_TARGET"
# Ensure it is writable
chmod 666 "$GPKG_TARGET"

# 3. Launch QField
echo "Launching QField..."
# Launching via VIEW intent to open the specific project immediately
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_TARGET" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for app to load
sleep 10

# 4. Dismiss any potential "Missing Project" or tutorial dialogs if they appear
# (Tap center/bottom to dismiss generic popups)
input tap 540 1800 2>/dev/null || true
sleep 1

echo "=== Setup complete ==="