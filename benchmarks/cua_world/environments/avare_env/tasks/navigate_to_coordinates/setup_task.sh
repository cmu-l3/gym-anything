#!/system/bin/sh
echo "=== Setting up navigate_to_coordinates task ==="

PACKAGE="com.ds.avare"

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean state
echo "Force stopping Avare..."
am force-stop $PACKAGE
sleep 2

# 3. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 4. Handle any potential startup dialogs/restore state
# Press Back once just in case a menu or dialog is open
input keyevent KEYCODE_BACK
sleep 1

# 5. Ensure we are on the map (re-launching usually brings to front)
# We assume the environment setup (setup_avare.sh) has already handled 
# the one-time registration and database download.

# 6. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="