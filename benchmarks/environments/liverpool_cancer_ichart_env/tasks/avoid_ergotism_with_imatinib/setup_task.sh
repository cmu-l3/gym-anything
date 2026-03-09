#!/system/bin/sh
echo "=== Setting up avoid_ergotism_with_imatinib task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

# Clean up any previous results
rm -f /sdcard/migraine_safety_check.txt
rm -f /sdcard/task_result.json

# Force stop the app to ensure clean state
am force-stop com.liverpooluni.ichartoncology
sleep 1

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

# Launch the app fresh
monkey -p com.liverpooluni.ichartoncology -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p com.liverpooluni.ichartoncology -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="