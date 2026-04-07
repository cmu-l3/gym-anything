#!/system/bin/sh
# Setup script for school_bus_safety_setup task.
# Resets safety features to off and distance units to km, so agent must enable all.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up school_bus_safety_setup task ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"

# Force stop for clean state
am force-stop $PACKAGE
sleep 2

# Remove any extra vehicle profiles (only keep Vehicle 1 / default)
EXTRA=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle WHERE id > 1;')
if [ "$EXTRA" -gt 0 ]; then
    echo "Removing $EXTRA extra vehicle profiles..."
    sqlite3 "$VEHICLE_DB" 'DELETE FROM vehicle WHERE id > 1;'
fi

# Record baseline
INITIAL_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle;')
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/school_bus_safety_setup_initial_vehicle_count
echo "Initial vehicle count: $INITIAL_VEHICLE_COUNT"

# Reset selected profile to default (Vehicle 1)
sed -i 's/name="selected_vehicle_profile_id" value="[^"]*"/name="selected_vehicle_profile_id" value="1"/' "$BASE_PREFS"
SELECTED_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/school_bus_safety_setup_initial_selected_id

# Set starting state (safety features off — agent must enable all):
# Arrive-in-direction = false -- must enable (true)
sed -i 's/name="preferenceKey_arriveInDrivingSide" value="[^"]*"/name="preferenceKey_arriveInDrivingSide" value="false"/' "$PREFS_FILE"

# Lane guidance = false -- must enable (true)
# Correct pref key includes "navigation_" prefix
sed -i 's/name="preferenceKey_navigation_laneGuidance" value="[^"]*"/name="preferenceKey_navigation_laneGuidance" value="false"/' "$PREFS_FILE"

# Avoid ferries = false -- must enable (true)
sed -i 's/name="tmp_preferenceKey_routePlanning_ferries_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_ferries_avoid" value="false"/' "$PREFS_FILE"

# Distance units = Km (1) -- must change to Miles (0)
sed -i 's|name="preferenceKey_regional_distanceUnitsFormat">[^<]*|name="preferenceKey_regional_distanceUnitsFormat">1|' "$PREFS_FILE"

# Record task start timestamp
date +%s > /data/local/tmp/school_bus_safety_setup_start_ts

# Press Home, then launch app
input keyevent KEYCODE_HOME
sleep 1

echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

screencap -p /data/local/tmp/school_bus_safety_setup_start_screenshot.png 2>/dev/null

echo "=== school_bus_safety_setup setup complete ==="
