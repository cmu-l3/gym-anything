#!/system/bin/sh
echo "=== Setting up view_ifr_low_chart task ==="

# Define paths
PACKAGE="com.ds.avare"
DATA_DIR="/sdcard/com.ds.avare"
START_TIME_FILE="/sdcard/task_start_time.txt"
INITIAL_FILE_LIST="/sdcard/initial_files.txt"

# Record task start time
date +%s > "$START_TIME_FILE"

# Clean up previous artifacts
rm -f /sdcard/ifr_chart_result.png
rm -f /sdcard/task_result.json

# Record initial state of map directory to detect downloads
# Avare typically stores maps in /sdcard/com.ds.avare/maps or similar
if [ -d "$DATA_DIR" ]; then
    ls -R "$DATA_DIR" > "$INITIAL_FILE_LIST"
else
    echo "Data dir not found yet" > "$INITIAL_FILE_LIST"
fi

# Ensure Avare is running and clean
am force-stop $PACKAGE
sleep 2

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are on the main map (press Back to dismiss potential menus/dialogs)
input keyevent KEYCODE_BACK
sleep 1

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="