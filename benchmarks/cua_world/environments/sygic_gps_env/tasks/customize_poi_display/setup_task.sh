#!/system/bin/sh
# Setup script for customize_poi_display task
# Runs inside the Android environment

echo "=== Setting up customize_poi_display task ==="

TASK_DIR="/sdcard/tasks/customize_poi_display"
mkdir -p "$TASK_DIR"

# 1. Clean up previous artifacts
rm -f "$TASK_DIR/poi_config_done.png"
rm -f "$TASK_DIR/task_result.json"
rm -f "$TASK_DIR/final_state.png"

# 2. Record task start time (anti-gaming)
date +%s > "$TASK_DIR/task_start_time.txt"

# 3. Reset App State (Force stop)
PACKAGE="com.sygic.aura"
echo "Force stopping Sygic..."
am force-stop $PACKAGE
sleep 2

# 4. Launch Sygic GPS
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Handle startup annoyances (if any)
# Try to dismiss "Your map is ready" bottom sheet or other popups
input tap 860 1510
sleep 2

# 6. Ensure we are on the map (Press back once just in case a menu was open, though fresh launch should be map)
# input keyevent KEYCODE_BACK
# sleep 1

echo "=== Setup complete ==="