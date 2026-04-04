#!/system/bin/sh
# Setup script for emergency_diversion_plan task.
# Clears any existing EMER.csv so the agent must create it fresh.

echo "=== Setting up emergency_diversion_plan ==="

PACKAGE="com.ds.avare"

am force-stop $PACKAGE
sleep 3

# Remove any pre-existing EMER plan
if [ -d /sdcard/avare/Plans ]; then
    rm -f /sdcard/avare/Plans/EMER.csv
    rm -f /sdcard/avare/Plans/emer.csv
    rm -f /sdcard/avare/Plans/Emer.csv
else
    mkdir -p /sdcard/avare/Plans
fi

# Record baseline
date +%s > /sdcard/avare_task_start_timestamp.txt

# Grant permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch Avare
input keyevent KEYCODE_HOME
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

CURRENT=$(dumpsys window | grep mCurrentFocus 2>/dev/null)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

screencap -p /sdcard/avare_emer_initial.png 2>/dev/null

echo "=== Setup complete ==="
