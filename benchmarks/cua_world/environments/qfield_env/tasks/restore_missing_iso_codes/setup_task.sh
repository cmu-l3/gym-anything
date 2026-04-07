#!/bin/bash
set -e
echo "=== Setting up restore_missing_iso_codes task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Android Path definitions
# Note: QField stores imported projects in private storage or Android/data
# The environment setup puts it in Android/data/.../Imported Datasets/
ANDROID_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
LOCAL_GPKG="/tmp/world_survey.gpkg"

# Check if ADB is available and connected
if ! adb devices | grep -q "device$"; then
    echo "ERROR: No Android device connected via ADB."
    exit 1
fi

echo "Pulling GeoPackage from device..."
rm -f "$LOCAL_GPKG"
adb pull "$ANDROID_GPKG" "$LOCAL_GPKG"

echo "Modifying GeoPackage Schema (adding iso_code)..."
# Use Python to reliably modify the SQLite/GeoPackage file
python3 -c "
import sqlite3
import sys

db_path = '$LOCAL_GPKG'
con = sqlite3.connect(db_path)
cur = con.cursor()

try:
    # Add column if it doesn't exist
    cur.execute('ALTER TABLE world_capitals ADD COLUMN iso_code TEXT')
    print('Column iso_code added.')
except sqlite3.OperationalError as e:
    if 'duplicate column name' in str(e):
        print('Column already exists, resetting values.')
        cur.execute('UPDATE world_capitals SET iso_code = NULL')
    else:
        raise e

# Add context examples
examples = {
    'Paris': 'FR',
    'Washington': 'US',
    'London': 'GB',
    'Berlin': 'DE'
}

for city, code in examples.items():
    cur.execute('UPDATE world_capitals SET iso_code = ? WHERE name = ?', (code, city))
    print(f'Set example: {city} -> {code}')

con.commit()
con.close()
"

echo "Pushing modified GeoPackage back to device..."
adb push "$LOCAL_GPKG" "$ANDROID_GPKG"
rm -f "$LOCAL_GPKG"

echo "Restarting QField..."
PACKAGE="ch.opengis.qfield"
adb shell am force-stop $PACKAGE
sleep 2

# Launch QField
# We launch the main activity. If QField was previously open, it might reload the last project.
# To be safe, we fire an intent to VIEW the specific file.
echo "Launching QField with project intent..."
adb shell am start -a android.intent.action.VIEW \
    -d \"file://$ANDROID_GPKG\" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity"

# Wait for app to load
sleep 10

# Capture initial screenshot
adb exec-out screencap -p > /tmp/task_initial.png

echo "=== Task setup complete ==="