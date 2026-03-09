#!/system/bin/sh
# Setup script for vfr_navaid_routing task.
# Clears existing plan files, records baseline, and launches Avare.
# Real airports used: KSFO (San Francisco International), KLAS (Las Vegas).
# The aviation database bundled with Avare contains these real airports and VOR navaids.

echo "=== Setting up vfr_navaid_routing task ==="

PACKAGE="com.ds.avare"

# Force stop to get a clean state
am force-stop $PACKAGE
sleep 3

# Remove any pre-existing saved plan files to prevent pre-existing plans
# from satisfying verification criteria (adversarial robustness)
if [ -d /sdcard/avare/Plans ]; then
    rm -f /sdcard/avare/Plans/*.csv
    echo "Cleared existing plan files"
else
    mkdir -p /sdcard/avare/Plans
    echo "Created Plans directory"
fi

# Record baseline: no plans exist at task start
echo "0" > /sdcard/avare_initial_plan_count.txt
date +%s > /sdcard/avare_task_start_timestamp.txt

echo "Baseline state recorded: no saved plans"

# Grant location permissions
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Press Home before launching
input keyevent KEYCODE_HOME
sleep 1

# Launch Avare to main map screen
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# Verify app is in foreground; retry if needed
CURRENT=$(dumpsys window | grep mCurrentFocus 2>/dev/null)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== vfr_navaid_routing task setup complete ==="
echo "Agent must build VFR route KSFO->intermediate navaids->KLAS (>=5 waypoints) and save plan."
