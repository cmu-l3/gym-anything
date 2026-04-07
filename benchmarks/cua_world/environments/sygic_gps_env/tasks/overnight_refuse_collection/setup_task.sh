#!/system/bin/sh
# Setup script for overnight_refuse_collection task.
# Resets to a known daytime/default state that does not match overnight truck requirements.
# Agent must create the Refuse Truck profile and adjust 4 settings.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up overnight_refuse_collection task ==="

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
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/overnight_refuse_collection_initial_vehicle_count
echo "Initial vehicle count: $INITIAL_VEHICLE_COUNT"

# Reset selected profile to default (Vehicle 1)
sed -i 's/name="selected_vehicle_profile_id" value="[^"]*"/name="selected_vehicle_profile_id" value="1"/' "$BASE_PREFS"
SELECTED_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/overnight_refuse_collection_initial_selected_id

# Set starting state (daytime defaults — agent must change all of these):
# Route compute = Fastest (1) -- must change to Shortest (0)
sed -i 's|name="preferenceKey_routePlanning_routeComputing">[^<]*|name="preferenceKey_routePlanning_routeComputing">1|' "$PREFS_FILE"

# Avoid highways = false -- must enable (true)
sed -i 's/name="tmp_preferenceKey_routePlanning_motorways_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_motorways_avoid" value="false"/' "$PREFS_FILE"

# App theme = Auto (0) -- must change to Night (2)
sed -i 's|name="preferenceKey_app_theme">[^<]*|name="preferenceKey_app_theme">0|' "$PREFS_FILE"

# Temperature units = Metric (Celsius) -- must change to Imperial (Fahrenheit)
sed -i 's|name="preferenceKey_weather_temperatureUnits">[^<]*|name="preferenceKey_weather_temperatureUnits">Metric|' "$PREFS_FILE"

# Record task start timestamp
date +%s > /data/local/tmp/overnight_refuse_collection_start_ts

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

screencap -p /data/local/tmp/overnight_refuse_collection_start_screenshot.png 2>/dev/null

echo "=== overnight_refuse_collection setup complete ==="
