#!/system/bin/sh
set -e
echo "=== Setting up check_herbal_interaction_with_imatinib task ==="

# Define paths
TASK_DIR="/sdcard/tasks/check_herbal_interaction_with_imatinib"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_FILE="/sdcard/interaction_result.txt"
PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time for anti-gaming verification
date +%s > "$START_TIME_FILE"

# Clean up previous results
rm -f "$RESULT_FILE"
rm -f "/sdcard/task_result.json"

# Ensure application is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart app not installed"
    exit 1
fi

# Force stop to ensure clean state
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 1

# Launch the app to the main activity
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 5

# Take initial state screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="