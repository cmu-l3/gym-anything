#!/system/bin/sh
# Setup script for audit_mislocated_capitals task.
# Corrupts specific attribute data in the GeoPackage to create the audit scenario.

echo "=== Setting up audit_mislocated_capitals task ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG_TASK="$DATA_DIR/world_survey.gpkg"

# Record start time for anti-gaming (using date +%s if available, else standard date)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || date > /sdcard/task_start_time.txt

# 1. Prepare the GeoPackage
# We need a writable copy in the app-accessible directory
echo "Preparing GeoPackage..."
mkdir -p "$DATA_DIR"
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"

# 2. Corrupt the data using sqlite3
# We update the latitude/longitude attributes to be wrong for 3 specific cities.
# We do NOT change the geometry (the dot stays on the map), making this an attribute audit task.
# We also clear the 'notes' field to ensure a clean state.

echo "Corrupting data attributes..."

# Tokyo (Japan) -> Moved to South Africa coords
sqlite3 "$GPKG_TASK" "UPDATE world_capitals SET latitude = -25.0, longitude = 28.0 WHERE name = 'Tokyo';"

# Ottawa (Canada) -> Moved to Australia coords
sqlite3 "$GPKG_TASK" "UPDATE world_capitals SET latitude = -33.9, longitude = 151.2 WHERE name = 'Ottawa';"

# Cairo (Egypt) -> Moved to Brazil coords
sqlite3 "$GPKG_TASK" "UPDATE world_capitals SET latitude = -15.8, longitude = -47.9 WHERE name = 'Cairo';"

# Ensure notes are empty for all audit targets
sqlite3 "$GPKG_TASK" "UPDATE world_capitals SET notes = '' WHERE name IN ('Tokyo', 'Ottawa', 'Cairo', 'Canberra', 'Buenos Aires', 'London');"

# 3. Launch QField
echo "Launching QField..."

# Force stop to ensure fresh reload of data
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch with VIEW intent to open the specific project
am start -a android.intent.action.VIEW \
    -d "file://$GPKG_TASK" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

sleep 5

# Check if launch succeeded
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent launch failed, trying fallback..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    # Allow extra time for project loading
    sleep 10
fi

# Dismiss any potential "Missing Project" or tutorial dialogs if they appear
# (Tap center/bottom just in case)
input tap 540 2000 2>/dev/null

echo "=== Task setup complete ==="
echo "Data corruption applied. QField launched."