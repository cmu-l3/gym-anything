#!/system/bin/sh
# Setup script for ALK Inhibitor Interaction Classification
# Runs inside Android environment

echo "=== Setting up ALK Inhibitor Audit Task ==="

PACKAGE="com.liverpooluni.ichartoncology"
RESULT_FILE="/sdcard/alk_transplant_audit.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. clean up previous artifacts
rm -f "$RESULT_FILE"
rm -f "/sdcard/task_result.json"
rm -f "/sdcard/final_screenshot.png"

# 2. Record start time (using date +%s if available, else standard date)
date +%s > "$START_TIME_FILE" 2>/dev/null || date > "$START_TIME_FILE"

# 3. Ensure app is closed
am force-stop "$PACKAGE"
sleep 2

# 4. Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch app to ensure it's ready
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Ensure we are on the main screen (if app restores state, try to reset)
# Note: The app usually resets on force-stop, but we ensure it's in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup Complete ==="