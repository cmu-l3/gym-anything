#!/system/bin/sh
# Setup script for perform_emergency_divert
# Ensures Avare is running and GPS Simulation is initially OFF

echo "=== Setting up Emergency Divert Task ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"

# Record start time
date +%s > /sdcard/task_start_time.txt

# Force stop to ensure we can modify prefs if needed and start fresh
am force-stop $PACKAGE
sleep 2

# Ensure we have a clean slate for simulation (turn it off if it was on)
# We use sed to replace true with false for the simulation setting if it exists
if [ -f "$PREFS_FILE" ]; then
    # Create backup for anti-gaming comparison
    cp "$PREFS_FILE" /sdcard/initial_prefs.xml
    chmod 666 /sdcard/initial_prefs.xml
    
    # Attempt to disable simulation mode in XML (SimulationMode is the likely key)
    # This is a best-effort text replacement
    sed -i 's/name="SimulationMode" value="true"/name="SimulationMode" value="false"/g' "$PREFS_FILE"
fi

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch Avare
echo "Launching Avare..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

# Wait for app to load
sleep 10

# Capture initial screenshot
screencap -p /sdcard/task_initial.png

echo "=== Setup Complete ==="