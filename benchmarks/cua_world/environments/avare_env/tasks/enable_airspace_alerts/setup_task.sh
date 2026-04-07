#!/system/bin/sh
# Setup script for enable_airspace_alerts task
# Runs on Android device

echo "=== Setting up enable_airspace_alerts task ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"

# 1. Force stop Avare to ensure clean state and allow pref modification
am force-stop $PACKAGE
sleep 2

# 2. Record start time (seconds since epoch)
date +%s > /sdcard/task_start_time.txt

# 3. Disable Airspace Alerts initially to force the agent to enable it
# We use sed to replace "true" with "false" for any key containing "Airspace"
# This ensures we start from a disabled state.
if [ -f "$PREFS_FILE" ]; then
    echo "Modifying preferences to disable airspace alerts..."
    # Create backup
    cp "$PREFS_FILE" "${PREFS_FILE}.bak"
    
    # Generic attempt to set common airspace keys to false
    # We look for lines with "Airspace" and value="true" and switch them
    sed -i 's/name=".*Airspace.*" value="true"/name="ShowAirspace" value="false"/g' "$PREFS_FILE"
    sed -i 's/name=".*Alarm.*" value="true"/name="AirspaceAlarm" value="false"/g' "$PREFS_FILE"
    
    # Ensure permissions are correct after modification
    chmod 660 "$PREFS_FILE"
    chown system:system "$PREFS_FILE" 2>/dev/null || true
else
    echo "Preferences file not found, will be created on launch."
fi

# 4. Clear any UI state by pressing Home
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 10

# 6. Ensure we are on the main screen (not in a menu from previous run)
# Pressing back a couple of times is a safe heuristic if stuck in a menu
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1

# If we backed out too far, relaunch
if ! dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

echo "=== Setup complete ==="