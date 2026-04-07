#!/system/bin/sh
# Setup script for configure_delivery_vehicle task.
# Ensures the app starts with only the default Vehicle 1 profile,
# route compute set to "Fastest", toll avoidance OFF, and arrive-in-direction OFF.

# Ensure root access for reading/writing app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up configure_delivery_vehicle task ==="

PACKAGE="com.sygic.aura"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Record baseline: count of vehicle profiles
INITIAL_VEHICLE_COUNT=$(sqlite3 /data/data/$PACKAGE/databases/vehicles-database 'SELECT COUNT(*) FROM vehicle;')
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/initial_vehicle_count
echo "Initial vehicle count: $INITIAL_VEHICLE_COUNT"

# Record selected vehicle profile ID
SELECTED_ID=$(cat /data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml 2>/dev/null | grep 'selected_vehicle_profile_id' | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/initial_selected_vehicle_id
echo "Initial selected vehicle ID: $SELECTED_ID"

# Reset route compute to Fastest (value "1") so the agent must change it
# Reset toll avoidance to false so the agent must verify it's already correct
# Reset arrive-in-direction to false so the agent must enable it
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Use sed to modify preferences in-place for route compute (set to fastest=1)
sed -i 's/name="preferenceKey_routePlanning_routeComputing">[^<]*/name="preferenceKey_routePlanning_routeComputing">1/' "$PREFS_FILE"

# Set toll avoidance to false
sed -i 's/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="false"/' "$PREFS_FILE"

# Set arrive-in-direction to false
sed -i 's/name="preferenceKey_arriveInDrivingSide" value="[^"]*"/name="preferenceKey_arriveInDrivingSide" value="false"/' "$PREFS_FILE"

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

echo "=== configure_delivery_vehicle task setup complete ==="
