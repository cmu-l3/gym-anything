#!/system/bin/sh
# Setup script for enable_school_zone_alerts task
# Runs inside the Android environment

echo "=== Setting up enable_school_zone_alerts task ==="

PACKAGE="com.sygic.aura"

# Record start time
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Press Home to clear any other overlays
input keyevent KEYCODE_HOME
sleep 1

# Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Ensure we are not stuck on a splash screen (simple tap center if needed, but monkey usually works)
# Verify app is in foreground
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    echo "Sygic launched successfully"
else
    echo "Retrying launch..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="