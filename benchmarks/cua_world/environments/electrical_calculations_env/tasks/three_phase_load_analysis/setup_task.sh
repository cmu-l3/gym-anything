#!/system/bin/sh
# Setup script for Three-Phase Load Analysis task

echo "=== Setting up Three-Phase Load Analysis ==="

# Force-stop the app to ensure a clean state
am force-stop com.hsn.electricalcalculations
sleep 1

# Go to home screen
input keyevent KEYCODE_HOME
sleep 1

# Launch the app
monkey -p com.hsn.electricalcalculations -c android.intent.category.LAUNCHER 1
sleep 8

# Dismiss any ads or overlays with BACK key
input keyevent KEYCODE_BACK
sleep 2

# Check if the app is running (fallback relaunch)
CURRENT=$(dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | grep "com.hsn")
if [ -z "$CURRENT" ]; then
    echo "App not in foreground, relaunching..."
    monkey -p com.hsn.electricalcalculations -c android.intent.category.LAUNCHER 1
    sleep 5
fi

# Record task start timestamp
date +%s > /sdcard/task_start_ts_three_phase_load.txt

echo "=== Setup Complete: Navigate to the three-phase power calculations ==="
