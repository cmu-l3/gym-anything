#!/system/bin/sh
echo "=== Setting up export_flight_plan_gpx task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up any previous attempts
# Remove specific file if it exists anywhere likely
find /sdcard -name "route_export.gpx" -delete 2>/dev/null
rm -f /sdcard/route_export.gpx 2>/dev/null
rm -f /sdcard/Download/route_export.gpx 2>/dev/null
rm -f /sdcard/com.ds.avare/route_export.gpx 2>/dev/null

# 3. Ensure Avare is in a clean state
PACKAGE="com.ds.avare"
am force-stop $PACKAGE
sleep 2

# 4. Grant storage permissions explicitly to ensure export works without permission dialogs
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.MANAGE_EXTERNAL_STORAGE 2>/dev/null

# 5. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 6. Ensure we are not stuck in a menu/dialog from previous runs
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# 7. Take initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="