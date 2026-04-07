#!/system/bin/sh
echo "=== Setting up set_auto_day_night_mode task ==="

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.sygic.aura"

# Force stop to ensure a clean state
am force-stop $PACKAGE
sleep 2

# Press Home to clear any other UI
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Handle potential "Resume" or "Rate us" dialogs by sending Back key once if needed, 
# but usually a fresh force-stop launch lands on the map.
# input keyevent KEYCODE_BACK
# sleep 1

# Ensure the app is in the foreground
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
echo "Current focus: $CURRENT_FOCUS"

# Capture initial screenshot for evidence
screencap -p /sdcard/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="