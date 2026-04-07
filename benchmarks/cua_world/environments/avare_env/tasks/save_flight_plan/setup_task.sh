#!/system/bin/sh
# Setup script for save_flight_plan task
# 1. Cleans up old plan files to prevent gaming
# 2. Launches Avare in a clean state

echo "=== Setting up save_flight_plan task ==="

PACKAGE="com.ds.avare"

# 1. Record task start time (using standard Unix timestamp)
date +%s > /sdcard/task_start_time.txt

# 2. Cleanup: Remove any existing plans with the target name
# Avare typically stores plans in app-specific storage or SD card
echo "Cleaning up old plans..."

# Try standard external storage paths
rm -f /sdcard/Android/data/$PACKAGE/files/plans/*BayAreaTraining* 2>/dev/null
rm -f /sdcard/com.ds.avare/plans/*BayAreaTraining* 2>/dev/null

# Try internal storage (requires root/shell permissions usually available in this env)
# Using run-as if possible, otherwise direct rm if root
if [ -d "/data/data/$PACKAGE" ]; then
    find /data/data/$PACKAGE -name "*BayAreaTraining*" -delete 2>/dev/null || true
fi

# 3. Ensure Avare is running and clean
echo "Restarting Avare..."
am force-stop $PACKAGE
sleep 2

# Grant permissions just in case
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null

# Launch app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 4. Capture initial state
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="