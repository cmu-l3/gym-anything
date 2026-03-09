#!/system/bin/sh
echo "=== Setting up check_ccb_interaction_with_olaparib task ==="

# Define paths
TASK_DIR="/sdcard/tasks/check_ccb_interaction_with_olaparib"
RESULT_FILE="/sdcard/tasks/interaction_result.txt"
START_TIME_FILE="/sdcard/tasks/task_start_time.txt"
PACKAGE="com.liverpooluni.ichartoncology"

# Create task directory if it doesn't exist (though mount usually handles this, ensure writeable areas exist)
mkdir -p /sdcard/tasks

# Clean up previous artifacts
rm -f "$RESULT_FILE"
rm -f "$START_TIME_FILE"
rm -f "/sdcard/tasks/task_result.json"
rm -f "/sdcard/tasks/final_screenshot.png"

# Record start time for anti-gaming verification
date +%s > "$START_TIME_FILE"

# Force stop the app to ensure clean state
echo "Force stopping Cancer iChart..."
am force-stop "$PACKAGE"
sleep 2

# Navigate to Home screen
input keyevent KEYCODE_HOME
sleep 2

# Launch the app fresh
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure app is in foreground (basic check)
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "App launched successfully."
else
    echo "WARNING: App might not be in foreground. Retrying launch..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot for debug/evidence
screencap -p /sdcard/tasks/initial_state.png 2>/dev/null

echo "=== Task setup complete ==="