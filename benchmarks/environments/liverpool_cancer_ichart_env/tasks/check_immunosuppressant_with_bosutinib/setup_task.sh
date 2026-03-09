#!/system/bin/sh
# Setup script for check_immunosuppressant_with_bosutinib task
echo "=== Setting up immunosuppressant interaction check task ==="

PACKAGE="com.liverpooluni.ichartoncology"

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Ensure app is installed
if ! pm list packages | grep -q "$PACKAGE"; then
    echo "ERROR: Cancer iChart not installed"
    exit 1
fi

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Clear any previous task artifacts
rm -f /sdcard/task_result.json 2>/dev/null
rm -f /sdcard/final_screenshot.png 2>/dev/null

# Launch the app fresh
# Uses monkey to launch the main activity
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Ensure we are on the main screen
# If the app was previously killed, it should start fresh. 
# We wait a bit to ensure it loads.
sleep 3

# Check if app is in foreground
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    echo "App launched successfully"
else
    echo "WARNING: App might not be in foreground. Retrying launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot for evidence
screencap -p /sdcard/initial_screenshot.png

echo "=== Task setup complete - app should be on main screen ==="