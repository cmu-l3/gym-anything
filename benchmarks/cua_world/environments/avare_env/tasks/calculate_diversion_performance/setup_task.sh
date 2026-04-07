#!/system/bin/sh
echo "=== Setting up calculate_diversion_performance task ==="

PACKAGE="com.ds.avare"

# 1. Record start time for anti-gaming (file modification checks)
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/diversion_calc.txt
rm -f /sdcard/task_prefs.xml
rm -f /sdcard/task_result.json

# 3. Ensure Avare is not running initially to allow clean start
am force-stop $PACKAGE
sleep 2

# 4. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# 5. Ensure we are on the Map screen (press Back a few times just in case)
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# If app closed, relaunch
if ! pidof com.ds.avare > /dev/null; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Task setup complete ==="