#!/system/bin/sh
echo "=== Setting up compare_analgesic_safety_methotrexate task ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks/compare_analgesic_safety_methotrexate"

# Ensure task directory exists
mkdir -p "$TASK_DIR"

# Clean up previous run artifacts
rm -f /sdcard/methotrexate_analgesic_report.txt
rm -f /sdcard/task_result.json
rm -f /sdcard/final_screenshot.png

# Record task start time (using date +%s if available, else a fallback)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || echo "0" > /sdcard/task_start_time.txt

# Force stop the app to ensure clean state
am force-stop "$PACKAGE"
sleep 2

# Press Home to ensure clean back stack
input keyevent KEYCODE_HOME
sleep 1

# Launch the app
echo "Launching Cancer iChart..."
monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Ensure app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot for evidence
screencap -p /sdcard/initial_screenshot.png 2>/dev/null

echo "=== Task setup complete ==="