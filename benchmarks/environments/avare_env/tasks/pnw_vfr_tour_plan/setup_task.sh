#!/system/bin/sh
# Setup script for pnw_vfr_tour_plan task.
# Starts with IFR Low chart so agent must switch to Sectional.
# Removes any existing PNW_TOUR plan.

echo "=== Setting up pnw_vfr_tour_plan ==="

PACKAGE="com.ds.avare"

am force-stop $PACKAGE
sleep 3

# Remove any pre-existing PNW_TOUR plan (case variants)
if [ -d /sdcard/avare/Plans ]; then
    rm -f /sdcard/avare/Plans/PNW_TOUR.csv
    rm -f /sdcard/avare/Plans/pnw_tour.csv
    rm -f /sdcard/avare/Plans/PNW_tour.csv
else
    mkdir -p /sdcard/avare/Plans
fi

# Attempt to seed chart type as IFR Low so agent must switch to Sectional
for PREFS_PATH in "/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml" \
                  "/data/user/0/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"; do
    if [ -f "$PREFS_PATH" ]; then
        sed -i 's/name="ChartType" *>[^<]*/name="ChartType">IFR Low/g' "$PREFS_PATH" 2>/dev/null
        break
    fi
done

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

screencap -p /sdcard/avare_pnw_initial.png 2>/dev/null

echo "=== Setup complete ==="
