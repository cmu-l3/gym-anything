#!/system/bin/sh
set -e
echo "=== Setting up document_pest_management task ==="

# Define paths
TASK_DIR="/sdcard/tasks/document_pest_management"
PACKAGE="org.farmos.app"

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

# Ensure the device is awake and unlocked
input keyevent KEYCODE_WAKEUP
input keyevent 82  # Unlock

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Clear app data to remove any previous logs (ensures 0 logs at start)
pm clear $PACKAGE
sleep 2

# Re-grant necessary permissions lost during clear
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true

# Launch the app
echo "Launching farmOS Field Kit..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Check if app is running and focused
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "App launched successfully."
else
    echo "WARNING: App not focused. Retrying launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="