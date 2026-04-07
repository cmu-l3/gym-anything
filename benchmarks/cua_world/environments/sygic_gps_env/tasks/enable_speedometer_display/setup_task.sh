#!/system/bin/sh
set -e
echo "=== Setting up Enable Speedometer Display task ==="

# Define paths
TASK_DIR="/sdcard/tasks/enable_speedometer_display"
mkdir -p "$TASK_DIR"

# Record task start time for anti-gaming verification
date +%s > "$TASK_DIR/task_start_time.txt"

PACKAGE="com.sygic.aura"

# Force stop to get clean launch state
am force-stop $PACKAGE
sleep 2

# Launch Sygic GPS
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Dismiss any "Your map is ready" or update bottom sheets that might block view
# Tapping roughly center-bottom to dismiss or X button if present
input tap 860 1510 2>/dev/null || true
sleep 2

# Take screenshot of initial state (map view without speedometer)
screencap -p "$TASK_DIR/initial_state.png"
echo "Initial state screenshot saved."

# Record initial UI dump to prove speedometer wasn't there
uiautomator dump "$TASK_DIR/initial_ui.xml" 2>/dev/null || true

echo "=== Task setup complete ==="