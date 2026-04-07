#!/system/bin/sh
echo "=== Setting up plan_vor_route task ==="

PACKAGE="com.ds.avare"

# 1. Record task start time (for anti-gaming)
date +%s > /sdcard/task_start_time.txt

# 2. Clean up any previous attempts (Remove existing plans)
# Avare typically stores plans in internal files or shared storage
echo "Cleaning up old plans..."
rm -f /data/data/com.ds.avare/files/plans/VOR_PRACTICE 2>/dev/null
rm -f /data/data/com.ds.avare/files/plans/VOR_PRACTICE.json 2>/dev/null
rm -f /sdcard/Android/data/com.ds.avare/files/plans/VOR_PRACTICE 2>/dev/null
rm -f /sdcard/Android/data/com.ds.avare/files/plans/VOR_PRACTICE.json 2>/dev/null

# 3. Ensure Avare is running and in a clean state
echo "Stopping Avare..."
am force-stop $PACKAGE
sleep 2

echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Handle any potential "Resume/Load" dialogs by sending BACK or CLEAR
# This helps ensure we start with a clean map/plan view
input keyevent KEYCODE_BACK
sleep 1

# 5. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="