#!/system/bin/sh
# Setup script for ifr_valley_routing task.
# Ensures Avare starts in a clean state with Sectional chart (agent must switch
# to IFR Low), and no saved plans.

echo "=== Setting up ifr_valley_routing ==="

PACKAGE="com.ds.avare"

# 1. Force-stop Avare to start clean
am force-stop $PACKAGE
sleep 3

# 2. Clean up any previous plan entries from the user database
su root sqlite3 /data/data/com.ds.avare/files/user.db "DELETE FROM plans;" 2>/dev/null
su root sqlite3 /data/user/0/com.ds.avare/files/user.db "DELETE FROM plans;" 2>/dev/null

# Also clean legacy CSV plan files if they exist
rm -f /sdcard/avare/Plans/*.csv 2>/dev/null
mkdir -p /sdcard/avare/Plans

# 3. Clean up previous result artifacts
rm -f /sdcard/task_result.json 2>/dev/null
rm -f /sdcard/task_initial.png 2>/dev/null
rm -f /sdcard/task_final.png 2>/dev/null
rm -f /sdcard/avare_ifr_valley_prefs.xml 2>/dev/null
rm -f /sdcard/avare_ifr_valley_plans.txt 2>/dev/null

# 4. Record task start time AFTER cleaning (anti-gaming: files must be newer)
date +%s > /sdcard/avare_task_start_timestamp.txt

# 5. Reset SharedPreferences: force Sectional chart so agent must switch to IFR Low
# The ChartType key may or may not exist; we handle both cases.
PREFS_DIR="/data/data/com.ds.avare/shared_prefs"
PREFS_DIR2="/data/user/0/com.ds.avare/shared_prefs"

reset_chart() {
    local PFILE="$1/com.ds.avare_preferences.xml"
    if [ -f "$PFILE" ]; then
        # If ChartType exists, set it to Sectional
        if su root grep -q 'ChartType' "$PFILE" 2>/dev/null; then
            su root sed -i 's|<string name="ChartType">[^<]*</string>|<string name="ChartType">Sectional</string>|g' "$PFILE" 2>/dev/null
        fi
        # If it doesn't exist, the default is already Sectional, so no action needed
    fi
}

reset_chart "$PREFS_DIR"
reset_chart "$PREFS_DIR2"

# 6. Grant required permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.MANAGE_EXTERNAL_STORAGE 2>/dev/null

# 7. Launch Avare
input keyevent KEYCODE_HOME
sleep 1
. /sdcard/scripts/launch_helper.sh
launch_avare

# 8. Wait for app to settle (no BACK key — it triggers the Exit dialog)
sleep 3

# 9. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png 2>/dev/null

echo "=== Setup complete ==="
