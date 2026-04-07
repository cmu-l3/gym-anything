#!/system/bin/sh
echo "=== Setting up change_voice_language task ==="

PACKAGE="com.sygic.aura"

# Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Launch Sygic GPS Navigation
echo "Launching Sygic GPS..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Dismiss any startup overlays or "map ready" sheets if they appear
# Tap X on bottom sheet if present (approx coords)
input tap 860 1510
sleep 1
# Press Back just in case
input keyevent KEYCODE_BACK
sleep 1

# Wait for main map view to stabilize
sleep 2

# Take screenshot of initial state
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="
echo "Sygic GPS launched. Ready for voice language change."