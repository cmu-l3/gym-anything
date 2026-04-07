#!/system/bin/sh
# Setup script for courier_urban_delivery task.
# Ensures a known starting state: only the default Vehicle 1, route set to Fastest,
# toll roads allowed, distance in miles, arrive-in-direction off.
# Agent must create the City Courier Van profile and configure all 4 additional settings.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up courier_urban_delivery task ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"

# Force stop for clean state
am force-stop $PACKAGE
sleep 2

# Remove any extra vehicle profiles so only Vehicle 1 (default) remains
EXTRA=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle WHERE id > 1;')
if [ "$EXTRA" -gt 0 ]; then
    echo "Removing $EXTRA extra vehicle profiles..."
    sqlite3 "$VEHICLE_DB" 'DELETE FROM vehicle WHERE id > 1;'
fi

# Record baseline vehicle count
INITIAL_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle;')
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/courier_urban_delivery_initial_vehicle_count
echo "Initial vehicle count: $INITIAL_VEHICLE_COUNT"

# Reset selected profile to default (Vehicle 1)
sed -i 's/name="selected_vehicle_profile_id" value="[^"]*"/name="selected_vehicle_profile_id" value="1"/' "$BASE_PREFS"
SELECTED_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/courier_urban_delivery_initial_selected_id
echo "Initial selected vehicle ID: $SELECTED_ID"

# Set starting state that the agent must fix:
# Route compute = Fastest (1) -- agent must change to Shortest (0)
sed -i 's|name="preferenceKey_routePlanning_routeComputing">[^<]*|name="preferenceKey_routePlanning_routeComputing">1|' "$PREFS_FILE"

# Toll roads NOT avoided (false) -- agent must set to avoid (true)
sed -i 's/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="false"/' "$PREFS_FILE"

# Distance units = Miles (0) -- agent must change to Km (1)
sed -i 's|name="preferenceKey_regional_distanceUnitsFormat">[^<]*|name="preferenceKey_regional_distanceUnitsFormat">0|' "$PREFS_FILE"

# Arrive-in-direction = false -- agent must enable (true)
sed -i 's/name="preferenceKey_arriveInDrivingSide" value="[^"]*"/name="preferenceKey_arriveInDrivingSide" value="false"/' "$PREFS_FILE"

# Record task start timestamp
date +%s > /data/local/tmp/courier_urban_delivery_start_ts
echo "Setup timestamp recorded."

# Press Home, then launch app
input keyevent KEYCODE_HOME
sleep 1

echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

# Re-launch if still on Launcher
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

screencap -p /data/local/tmp/courier_urban_delivery_start_screenshot.png 2>/dev/null

echo "=== courier_urban_delivery setup complete ==="
