#!/system/bin/sh
# Setup script for ifr_transcontinental_routing task.
# Starts with Sectional chart so agent must switch to IFR Low.
# Clears existing plans.

echo "=== Setting up ifr_transcontinental_routing ==="

PACKAGE="com.ds.avare"

am force-stop $PACKAGE
sleep 3

# Clear pre-existing plan files
if [ -d /sdcard/avare/Plans ]; then
    rm -f /sdcard/avare/Plans/*.csv
else
    mkdir -p /sdcard/avare/Plans
fi

# Attempt to reset chart type in SharedPreferences to Sectional
# so agent must change it to IFR Low
for PREFS_PATH in "/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml" \
                  "/data/user/0/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"; do
    if [ -f "$PREFS_PATH" ]; then
        # Replace any existing chart type string with Sectional
        sed -i 's/name="ChartType" *>[^<]*/name="ChartType">Sectional/g' "$PREFS_PATH" 2>/dev/null
        break
    fi
done

echo "0" > /sdcard/avare_trans_initial_plan_count.txt
date +%s > /sdcard/avare_task_start_timestamp.txt

pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

input keyevent KEYCODE_HOME
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

CURRENT=$(dumpsys window | grep mCurrentFocus 2>/dev/null)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

screencap -p /sdcard/avare_trans_initial.png 2>/dev/null

echo "=== Setup complete ==="
