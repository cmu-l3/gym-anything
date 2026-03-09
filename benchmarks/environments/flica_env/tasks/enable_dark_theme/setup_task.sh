#!/system/bin/sh
# Setup script for enable_dark_theme task
# Ensures app is logged in, system is in Light mode, and initial screenshot is captured

set -e
echo "=== Setting up Enable Dark Theme task ==="

# 1. Record task start time (Anti-gaming)
date +%s > /sdcard/task_start_time.txt

# 2. Ensure system is in LIGHT mode (reset to known state)
echo "Ensuring system is in Light mode..."
cmd uimode night no
sleep 2

# 3. Run login helper to get to Friends page
echo "Running login helper..."
sh /sdcard/scripts/login_helper.sh
sleep 5

# 4. Verify we're in the app
PACKAGE="com.robert.fcView"
CURRENT=$(dumpsys window | grep -i "mCurrentFocus" | head -1)
echo "Current focus: $CURRENT"

if ! echo "$CURRENT" | grep -q "$PACKAGE"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 5. Take initial screenshot (light mode reference)
# Using /sdcard/task_initial.png as standard name for verifier
screencap -p /sdcard/task_initial.png
echo "Initial screenshot saved to /sdcard/task_initial.png"

# 6. Verify Light mode applied
NIGHT_STATUS=$(cmd uimode night 2>&1)
echo "Initial Night mode status: $NIGHT_STATUS"

echo "=== Setup complete ==="
echo "App is on Friends page in Light mode."
echo "Agent should enable Dark theme and return to the app."