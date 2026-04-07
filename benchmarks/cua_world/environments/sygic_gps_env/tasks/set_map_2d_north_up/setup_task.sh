#!/system/bin/sh
set -e
echo "=== Setting up set_map_2d_north_up task ==="

TASK_DIR="/sdcard/tasks/set_map_2d_north_up"
PACKAGE="com.sygic.aura"

# Create task directory
mkdir -p "$TASK_DIR"

# Record task start time
date +%s > "$TASK_DIR/task_start_time.txt"

# Clear previous artifacts to prevent gaming
rm -f "$TASK_DIR/settings_confirmation.png"
rm -f "$TASK_DIR/final_map_view.png"
rm -f "$TASK_DIR/task_result.json"

# Force stop app to ensure clean start
am force-stop "$PACKAGE"
sleep 2

# Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load (simple sleep)
sleep 10

# Dismiss any potential "rate us" or premium popups by sending BACK key once
# (Be careful not to exit app if no popup exists, but one back is usually safe or ignored on map)
# input keyevent KEYCODE_BACK
# sleep 1

# Capture initial state screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Task setup complete ==="