#!/system/bin/sh
set -e
echo "=== Setting up download_terrain_data task ==="

PACKAGE="com.ds.avare"

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Identify data directory
DATA_DIR=""
for dir in "/sdcard/com.ds.avare" "/storage/emulated/0/Android/data/com.ds.avare/files" "/sdcard/avare"; do
    if [ -d "$dir" ]; then
        DATA_DIR="$dir"
        break
    fi
done

# If no dir found, create default to ensure we have a place to check
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/sdcard/com.ds.avare"
    mkdir -p "$DATA_DIR"
fi
echo "$DATA_DIR" > /sdcard/avare_data_dir.txt

# 3. Clean up existing terrain data to ensure fresh download
# (We want to force the agent to actually download it)
echo "Cleaning old terrain data in $DATA_DIR..."
find "$DATA_DIR" -type f -name "*terrain*" -delete 2>/dev/null || true
find "$DATA_DIR" -type f -name "*.t" -delete 2>/dev/null || true
find "$DATA_DIR" -type f -name "*elev*" -delete 2>/dev/null || true

# 4. Record initial file state (should be clean of terrain data now)
echo "Recording initial filesystem state..."
ls -lR "$DATA_DIR" > /sdcard/initial_file_list.txt 2>/dev/null || echo "No files" > /sdcard/initial_file_list.txt

# 5. Launch Avare
echo "Launching Avare..."
am force-stop $PACKAGE
sleep 2
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 6. Ensure we are on Map screen (dismiss any startup tips/dialogs)
# Tap center screen to dismiss potential "What's New" or tips
input tap 540 1200
sleep 2
# Tap again just in case
input tap 540 1200
sleep 2

# 7. Take initial screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== download_terrain_data task setup complete ==="