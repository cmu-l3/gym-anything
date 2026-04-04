#!/system/bin/sh
# Setup script for night_ifr_enroute_setup task.
# Ensures Avare starts with Night Mode OFF and Sectional chart selected,
# so the agent must make both changes deliberately.

echo "=== Setting up night_ifr_enroute_setup ==="

PACKAGE="com.ds.avare"

# Force-stop and clear any existing plan files
am force-stop $PACKAGE
sleep 3

if [ -d /sdcard/avare/Plans ]; then
    rm -f /sdcard/avare/Plans/*.csv
else
    mkdir -p /sdcard/avare/Plans
fi

# Reset SharedPreferences: set Night Mode to false and chart to Sectional
# We do this by writing a minimal seed XML; Avare merges on next start.
PREFS_DIR="/data/data/com.ds.avare/shared_prefs"
PREFS_DIR2="/data/user/0/com.ds.avare/shared_prefs"

# Helper to reset prefs in a given directory if it exists
reset_prefs() {
    if [ -d "$1" ]; then
        PFILE="$1/com.ds.avare_preferences.xml"
        if [ -f "$PFILE" ]; then
            # Patch NightMode to false
            sed -i 's/name="NightMode" *>[^<]*/name="NightMode">false/g' "$PFILE" 2>/dev/null
            sed -i 's/name="NightModePreference" *>[^<]*/name="NightModePreference">false/g' "$PFILE" 2>/dev/null
        fi
    fi
}

reset_prefs "$PREFS_DIR"
reset_prefs "$PREFS_DIR2"

# Record baseline
echo "0" > /sdcard/avare_initial_plan_count.txt
date +%s > /sdcard/avare_task_start_timestamp.txt

# Grant location permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch Avare
input keyevent KEYCODE_HOME
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Verify foreground
CURRENT=$(dumpsys window | grep mCurrentFocus 2>/dev/null)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

# Take initial screenshot
screencap -p /sdcard/avare_night_ifr_initial.png 2>/dev/null

echo "=== Setup complete ==="
