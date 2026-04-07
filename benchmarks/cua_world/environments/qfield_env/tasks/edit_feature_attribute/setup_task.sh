#!/system/bin/sh
echo "=== Setting up edit_feature_attribute task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
SRC_GPKG="/sdcard/QFieldData/world_survey.gpkg"
# Use the "Imported Datasets" path which is standard for QField external storage
WORK_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
WORK_GPKG="$WORK_DIR/world_survey.gpkg"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Force stop QField to ensure clean state
am force-stop $PACKAGE
sleep 2

# 3. Prepare Data
echo "Preparing GeoPackage..."
mkdir -p "$WORK_DIR"
# Copy fresh file from read-only source
cp "$SRC_GPKG" "$WORK_GPKG"
chmod 666 "$WORK_GPKG"

# 4. Set Initial Database State
# We need to ensure the 'description' column exists and has the sentinel value
if [ -f /system/bin/sqlite3 ]; then
    echo "Configuring database state with sqlite3..."
    
    # Try to add column (ignore error if exists)
    /system/bin/sqlite3 "$WORK_GPKG" "ALTER TABLE world_capitals ADD COLUMN description TEXT;" 2>/dev/null || true
    
    # Set the sentinel value for Paris
    # This ensures the agent must actively change it, and we can detect "do nothing"
    /system/bin/sqlite3 "$WORK_GPKG" "UPDATE world_capitals SET description = 'No survey data' WHERE name = 'Paris';"
    
    # Verify the setup
    CHECK_VAL=$(/system/bin/sqlite3 "$WORK_GPKG" "SELECT description FROM world_capitals WHERE name = 'Paris';")
    echo "Initial 'Paris' description set to: '$CHECK_VAL'"
else
    echo "ERROR: sqlite3 binary not found in /system/bin/. Task setup incomplete."
    # We continue, but verification might be harder if DB wasn't prepped
fi

# 5. Launch QField directly into the project
# Using VIEW intent ensures the specific file is opened
echo "Launching QField with project..."
am start -a android.intent.action.VIEW \
    -d "file://$WORK_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# 6. Wait for app to load
# We wait long enough for the map to render
sleep 12

# 7. Take initial screenshot (using screencap on Android)
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="