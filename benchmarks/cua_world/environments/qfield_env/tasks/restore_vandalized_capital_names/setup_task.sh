#!/system/bin/sh
set -e
echo "=== Setting up Restore Vandalized Capital Names task ==="

# Define paths
PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG_PATH="$DATA_DIR/world_survey.gpkg"
BACKUP_SRC="/sdcard/QFieldData/world_survey.gpkg"

# 1. Force stop QField to ensure file access
am force-stop $PACKAGE
sleep 2

# 2. Reset Data: Copy fresh GeoPackage from read-only mount
echo "Restoring clean GeoPackage..."
mkdir -p "$DATA_DIR"
cp "$BACKUP_SRC" "$GPKG_PATH"
chmod 666 "$GPKG_PATH"

# 3. Corrupt the database using sqlite3
# Note: sqlite3 is typically available in Android shell. If not, we might fail here, 
# but QField environment usually includes standard tools.
echo "Corrupting database entries..."

if ! command -v sqlite3 >/dev/null; then
    echo "ERROR: sqlite3 not found. Cannot set up task."
    exit 1
fi

# Corrupt Paris (France) -> Target_Alpha
sqlite3 "$GPKG_PATH" "UPDATE world_capitals SET name='Target_Alpha' WHERE name='Paris';"

# Corrupt Tokyo (Japan) -> Target_Bravo
sqlite3 "$GPKG_PATH" "UPDATE world_capitals SET name='Target_Bravo' WHERE name='Tokyo';"

# Corrupt Canberra (Australia) -> Target_Charlie
sqlite3 "$GPKG_PATH" "UPDATE world_capitals SET name='Target_Charlie' WHERE name='Canberra';"

# Verify corruption count
COUNT=$(sqlite3 "$GPKG_PATH" "SELECT count(*) FROM world_capitals WHERE name LIKE 'Target_%';")
echo "Corrupted features count: $COUNT"
if [ "$COUNT" -ne "3" ]; then
    echo "ERROR: Corruption failed. Expected 3, got $COUNT"
    exit 1
fi

# 4. Record task start timestamp (for anti-gaming)
date +%s > /sdcard/task_start_time.txt
# Record file modification time
stat -c %Y "$GPKG_PATH" > /sdcard/initial_mod_time.txt

# 5. Launch QField
echo "Launching QField..."
# Go to home first
input keyevent KEYCODE_HOME
sleep 1

# Launch app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 6. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="