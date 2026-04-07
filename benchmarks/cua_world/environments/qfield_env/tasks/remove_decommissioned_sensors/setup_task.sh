#!/system/bin/sh
# Setup script for remove_decommissioned_sensors task
# Runs inside the Android environment

echo "=== Setting up remove_decommissioned_sensors task ==="

# 1. Prepare Paths
PACKAGE="ch.opengis.qfield"
SOURCE_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# QField app-specific storage (writable and visible to app)
DEST_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
DEST_GPKG="$DEST_DIR/world_survey.gpkg"
TIMESTAMP_FILE="/sdcard/task_start_time.txt"

# 2. Record Start Time
date +%s > "$TIMESTAMP_FILE"

# 3. Clean and Prepare GeoPackage
echo "Preparing GeoPackage..."
mkdir -p "$DEST_DIR"

# Copy fresh world_survey.gpkg
cp "$SOURCE_GPKG" "$DEST_GPKG"
chmod 666 "$DEST_GPKG"

# 4. Inject Scenario Data (Active/Decommissioned Sensors)
# We update the first 6 existing observations to be our 'Sensors'
# IDs 1-3: Active
# IDs 4-6: Decommissioned

if [ -f "/system/bin/sqlite3" ] || [ -f "/vendor/bin/sqlite3" ]; then
    SQLITE="sqlite3"
else
    echo "WARNING: sqlite3 not found in path, trying generic call"
    SQLITE="sqlite3"
fi

echo "Injecting sensor data into $DEST_GPKG..."

# Update ID 1-3 to be Active Sensors
$SQLITE "$DEST_GPKG" "UPDATE field_observations SET name='Sensor '||id, notes='Status: Active' WHERE id IN (1, 2, 3);"

# Update ID 4-6 to be Decommissioned Sensors
$SQLITE "$DEST_GPKG" "UPDATE field_observations SET name='Sensor '||id, notes='Status: Decommissioned' WHERE id IN (4, 5, 6);"

# Verify injection
COUNT_ACTIVE=$($SQLITE "$DEST_GPKG" "SELECT count(*) FROM field_observations WHERE notes LIKE '%Active%';")
COUNT_DECOM=$($SQLITE "$DEST_GPKG" "SELECT count(*) FROM field_observations WHERE notes LIKE '%Decommissioned%';")
echo "Setup Verification: Active=$COUNT_ACTIVE, Decommissioned=$COUNT_DECOM"

# 5. Launch QField
echo "Launching QField..."
# Force stop to ensure clean reload
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch directly into the project via VIEW intent
# This ensures the map opens with the modified data loaded
am start -a android.intent.action.VIEW \
    -d "file://$DEST_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for load
sleep 10

# 6. Capture Initial State Screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="