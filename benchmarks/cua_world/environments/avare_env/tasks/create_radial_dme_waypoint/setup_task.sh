#!/system/bin/sh
set -e
echo "=== Setting up create_radial_dme_waypoint task ==="

# Record task start time
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.ds.avare"
DATA_DIR="/data/data/com.ds.avare/files"
EXTERNAL_DIR="/sdcard/com.ds.avare"

# Force stop to ensure clean state
am force-stop $PACKAGE
sleep 2

# Clean up existing plans to ensure we start empty
# Avare stores the current plan in 'save.json' or 'plans/Current.plan' depending on version
# We will try to clean common locations
echo "Clearing active flight plan..."
rm -f "$EXTERNAL_DIR/plans/Current.plan" 2>/dev/null || true
rm -f "$DATA_DIR/plans/Current.plan" 2>/dev/null || true

# Also clear the state file that remembers the last plan
rm -f "$DATA_DIR/save.json" 2>/dev/null || true

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Ensure we are on the Map screen (press Back a few times to clear menus if any)
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# Center map on SJC area (approximate) to help context
# We can't easily programmatically pan, but we can rely on the default state 
# or the agent's ability to find SJC. 
# The default setup script usually sets a location.

# Take initial screenshot
screencap -p /sdcard/task_initial_state.png

echo "=== Task setup complete ==="