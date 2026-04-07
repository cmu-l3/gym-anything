#!/system/bin/sh
# Setup script for mark_equatorial_hubs task
# Android environment

echo "=== Setting up Mark Equatorial Hubs task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_SOURCE="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TARGET="$DATA_DIR/world_survey.gpkg"

# 1. Record Start Time
date +%s > /data/local/tmp/task_start_time.txt

# 2. Prepare Data
# Ensure directory exists
mkdir -p "$DATA_DIR"

# Clean up any previous run's data to ensure a fresh start
rm -f "$GPKG_TARGET"
rm -f "$GPKG_TARGET-wal"
rm -f "$GPKG_TARGET-shm"

# Copy fresh GeoPackage
echo "Copying fresh GeoPackage..."
cp "$GPKG_SOURCE" "$GPKG_TARGET"
chmod 666 "$GPKG_TARGET"

# 3. Record Initial State (Feature Count)
# We use sqlite3 if available on the android image, otherwise we rely on file hash/size later
if command -v sqlite3 >/dev/null 2>&1; then
    INITIAL_COUNT=$(sqlite3 "$GPKG_TARGET" "SELECT COUNT(*) FROM field_observations;")
    echo "$INITIAL_COUNT" > /data/local/tmp/initial_count.txt
    echo "Initial feature count: $INITIAL_COUNT"
else
    echo "sqlite3 not found, skipping initial count query."
    echo "0" > /data/local/tmp/initial_count.txt
fi

# 4. Launch Application
echo "Force stopping QField..."
am force-stop $PACKAGE
sleep 2

echo "Launching QField..."
# Launching via VIEW intent to open the specific project immediately
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_TARGET" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# 5. Wait for Load & Dismiss Dialogs
sleep 10

# Dismiss potential "Missing project file" or "Project tutorial" dialogs if they appear
# Tapping center-ish bottom to hit "Next" or "Close" just in case
input tap 540 2000
sleep 1

echo "=== Task setup complete ==="