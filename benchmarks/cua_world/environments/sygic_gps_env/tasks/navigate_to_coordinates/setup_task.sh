#!/system/bin/sh
echo "=== Setting up navigate_to_coordinates task ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/navigate_to_coordinates"

# Ensure task directory exists
mkdir -p "$TASK_DIR"

# 1. Record start time for anti-gaming checks
date +%s > "$TASK_DIR/start_time.txt"

# 2. Force stop app to ensure clean state
am force-stop "$PACKAGE"
sleep 2

# 3. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 10

# 4. Handle potential blocking dialogs (First Run / Whats New)
# Tap Back once to dismiss any overlay menus
input keyevent KEYCODE_BACK
sleep 1

# 5. Ensure we are on the main map view
# If a menu is open, this might close it. If we are on Home, this does nothing harmful usually.
# Just ensuring we aren't stuck in a deep menu from a previous run (though force-stop helps).
input keyevent KEYCODE_BACK
sleep 1

# 6. Capture initial state screenshot
screencap -p "$TASK_DIR/initial_state.png"

echo "=== Setup complete ==="