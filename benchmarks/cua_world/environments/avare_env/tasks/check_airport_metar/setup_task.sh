#!/system/bin/sh
# Setup script for check_airport_metar task

echo "=== Setting up check_airport_metar task ==="

# Record task start time for anti-gaming
date +%s > /sdcard/task_start_time.txt

PACKAGE="com.ds.avare"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Clear any previous screenshots/artifacts
rm -f /sdcard/final_screenshot.png 2>/dev/null
rm -f /sdcard/ui_dump.xml 2>/dev/null
rm -f /sdcard/task_result.json 2>/dev/null

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 8

# Handle potential "Required data file missing" dialog or "Download" prompt
# We press BACK once to dismiss any modal dialogs that might block the map
input keyevent KEYCODE_BACK
sleep 2

# Re-launch if we accidentally backed out of the app
CURRENT_FOCUS=$(dumpsys window windows 2>/dev/null | grep -i "mCurrentFocus" || true)
if echo "$CURRENT_FOCUS" | grep -qi "launcher"; then
    echo "Re-launching Avare..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
fi

echo "=== Task setup complete ==="
echo "Agent should see Avare's main map view"