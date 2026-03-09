#!/system/bin/sh
# Setup script for Single-Phase Power Quality Audit task

echo "=== Setting up Single-Phase Power Quality Audit ==="

# Force-stop the app for a clean state
am force-stop com.hsn.electricalcalculations
sleep 1

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch the app
monkey -p com.hsn.electricalcalculations -c android.intent.category.LAUNCHER 1
sleep 8

# Dismiss any ads or overlays
input keyevent KEYCODE_BACK
sleep 2

# Verify app launched
CURRENT=$(dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | grep "com.hsn")
if [ -z "$CURRENT" ]; then
    echo "App not in foreground, relaunching..."
    monkey -p com.hsn.electricalcalculations -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# Record task start timestamp
date +%s > /sdcard/task_start_ts_sp_power.txt

echo "=== Setup Complete: Navigate to single-phase power calculations ==="
