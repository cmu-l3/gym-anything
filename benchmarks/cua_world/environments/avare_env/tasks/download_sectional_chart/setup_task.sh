#!/system/bin/sh
# Setup script for download_sectional_chart task
# Runs inside the Android environment

echo "=== Setting up download_sectional_chart task ==="

PACKAGE="com.ds.avare"
DATA_DIR="/sdcard/com.ds.avare"

# 1. Force stop app to ensure clean state
am force-stop $PACKAGE
sleep 2

# 2. Clear specific chart data (San Francisco Sectional)
# We want to force the agent to download it again.
# Avare tiles are typically in /sdcard/com.ds.avare/tiles/sectional/... or named files
echo "Clearing existing San Francisco chart data..."
rm -rf "$DATA_DIR/SanFrancisco"* 2>/dev/null
rm -rf "$DATA_DIR/tiles/sec/SanFrancisco"* 2>/dev/null
rm -rf "$DATA_DIR/tiles/sectional/SanFrancisco"* 2>/dev/null

# 3. Record initial file state for verification
# We count files in the data directory to compare later
INITIAL_FILE_COUNT=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)
echo "$INITIAL_FILE_COUNT" > /sdcard/initial_file_count.txt
echo "Initial file count: $INITIAL_FILE_COUNT"

# 4. Record task start time (using standard Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 5. Launch Avare to the main map screen
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 6. Handle potential startup dialogs
# If "Required data missing" appears (unlikely if DB is there, but possible), dismiss it
# Tapping 'Cancel' (right button usually) or Back
input keyevent KEYCODE_BACK
sleep 2

# Ensure we are on the map screen (focus)
input keyevent KEYCODE_FOCUS
sleep 1

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="