#!/system/bin/sh
# Setup script for create_custom_checklist task
# Launches Avare to the main map screen and ensures clean state

echo "=== Setting up create_custom_checklist task ==="

PACKAGE="com.ds.avare"

# Record start time for anti-gaming (using system uptime or date if available)
date +%s > /sdcard/task_start_time.txt

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Press Home to reset UI stack
input keyevent KEYCODE_HOME
sleep 1

# Grant permissions to ensure no popups block the agent
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null
pm grant $PACKAGE android.permission.READ_EXTERNAL_STORAGE 2>/dev/null

# Launch app
echo "Launching Avare..."
. /sdcard/scripts/launch_helper.sh
launch_avare

echo "=== Setup complete ==="