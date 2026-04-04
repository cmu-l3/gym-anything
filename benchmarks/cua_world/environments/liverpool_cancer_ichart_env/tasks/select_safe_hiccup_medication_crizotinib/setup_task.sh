#!/system/bin/sh
echo "=== Setting up select_safe_hiccup_medication_crizotinib task ==="

# Define paths
TASK_DIR="/sdcard/tasks/select_safe_hiccup_medication_crizotinib"
OUTPUT_FILE="/sdcard/hiccup_safety.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f "$START_TIME_FILE"
rm -f /sdcard/task_result.json

# 2. Record start time for anti-gaming verification
date +%s > "$START_TIME_FILE"

# 3. Ensure clean app state
PACKAGE="com.liverpooluni.ichartoncology"
echo "Force stopping app..."
am force-stop "$PACKAGE"
sleep 1

# 4. Return to Home Screen
echo "Going to home screen..."
input keyevent KEYCODE_HOME
sleep 2

# 5. Launch App to ensure it's ready
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Take initial screenshot evidence
screencap -p /sdcard/initial_state.png

echo "=== Setup complete ==="