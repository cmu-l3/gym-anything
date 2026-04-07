#!/system/bin/sh
# Setup script for optimize_highway_navigation task.
# Sets all target preferences to their OPPOSITE (pre-task) values,
# so the agent must change them to complete the task.
# Then launches Sygic GPS to the main map screen.

# Ensure root access for reading/writing app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up optimize_highway_navigation task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Force stop to get clean state and ensure prefs are flushed to disk
am force-stop $PACKAGE
sleep 2

# --- Set all preferences to their OPPOSITE (setup) values ---

# Route avoidances: all ON (true) so agent must disable highways and tolls
# (unpaved should stay true, so we set it true here too)
sed -i 's/name="tmp_preferenceKey_routePlanning_motorways_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_motorways_avoid" value="true"/' "$PREFS_FILE"
sed -i 's/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="true"/' "$PREFS_FILE"
sed -i 's/name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="true"/' "$PREFS_FILE"

# Route compute: set to Shortest ("0") so agent must change to Fastest ("1")
sed -i 's/name="preferenceKey_routePlanning_routeComputing">[^<]*/name="preferenceKey_routePlanning_routeComputing">0/' "$PREFS_FILE"

# Compass: OFF (false) so agent must enable it
sed -i 's/name="preferenceKey_navigation_compassAlwaysOn" value="[^"]*"/name="preferenceKey_navigation_compassAlwaysOn" value="false"/' "$PREFS_FILE"

# Driving mode: 3D ("1") so agent must switch to 2D ("0")
sed -i 's/name="preferenceKey_drivingMode">[^<]*/name="preferenceKey_drivingMode">1/' "$PREFS_FILE"

# 3D terrain: ON (true) so agent must disable it
# Key may not exist yet; insert before </map> if missing
if grep -q 'preferenceKey_map_3dTerrain' "$PREFS_FILE"; then
    sed -i 's/name="preferenceKey_map_3dTerrain" value="[^"]*"/name="preferenceKey_map_3dTerrain" value="true"/' "$PREFS_FILE"
else
    sed -i 's|</map>|    <boolean name="preferenceKey_map_3dTerrain" value="true" />\n</map>|' "$PREFS_FILE"
fi

# Font size: default ("0") so agent must change to bigger ("1")
sed -i 's/name="preferenceKey_map_fontSize">[^<]*/name="preferenceKey_map_fontSize">0/' "$PREFS_FILE"

echo "Preferences reset to setup values."

# --- Record baseline values for gate check ---
BASELINE_ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" | sed 's/.*>\(.*\)<.*/\1/')
BASELINE_DRIVING_MODE=$(grep 'preferenceKey_drivingMode' "$PREFS_FILE" | sed 's/.*>\(.*\)<.*/\1/')
echo "$BASELINE_ROUTE_COMPUTE" > /data/local/tmp/baseline_route_compute
echo "$BASELINE_DRIVING_MODE" > /data/local/tmp/baseline_driving_mode
echo "Baseline route_compute=$BASELINE_ROUTE_COMPUTE driving_mode=$BASELINE_DRIVING_MODE"

# Record timestamp
date +%s > /data/local/tmp/task_start_timestamp

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

# Take initial screenshot
screencap -p /data/local/tmp/task_start_screenshot.png 2>/dev/null

echo "=== optimize_highway_navigation task setup complete ==="
echo "App should be on main map screen. Agent must configure settings across Route planning & Navigation and View & Units pages."
