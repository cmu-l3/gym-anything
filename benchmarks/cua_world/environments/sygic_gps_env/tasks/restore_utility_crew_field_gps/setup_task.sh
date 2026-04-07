#!/system/bin/sh
# Setup script for restore_utility_crew_field_gps task.
# Pattern: Error Injection — seeds a personal car/commuter config.
# Key twist: avoid_unpaved is set to true but should be FALSE for utility crew
# (they need access to unpaved service roads at pipeline/valve sites).

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up restore_utility_crew_field_gps task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PLACES_DB="/data/data/$PACKAGE/databases/places-database"

# Step 1: Stop app and clean
am force-stop $PACKAGE
sleep 2

rm -f /data/local/tmp/restore_utility_crew_field_gps_result.json

# Remove vehicles from prior runs
sqlite3 "$VEHICLE_DB" "DELETE FROM vehicle WHERE name LIKE '%Commuter%' OR name LIKE '%commuter%' OR name LIKE '%Utility%' OR name LIKE '%utility%' OR name LIKE '%Field%' OR name LIKE '%field%' OR name LIKE '%Service%' OR name LIKE '%service%' OR name LIKE '%Office%' OR name LIKE '%office%';" 2>/dev/null

# Step 2: INJECT WRONG VEHICLE — personal sedan
sqlite3 "$VEHICLE_DB" "INSERT INTO vehicle (type, fuelType, name, productionYear, emissionCategory, maxSpeedKmh) VALUES ('CAR', 'GAS', 'Office Commuter', 2023, 'EURO6', 180);" 2>/dev/null

WRONG_VEH_ID=$(sqlite3 "$VEHICLE_DB" "SELECT id FROM vehicle WHERE name='Office Commuter' LIMIT 1;" 2>/dev/null)
if [ -n "$WRONG_VEH_ID" ]; then
    sed -i "s|name=\"selected_vehicle_profile_id\" value=\"[^\"]*\"|name=\"selected_vehicle_profile_id\" value=\"$WRONG_VEH_ID\"|" "$BASE_PREFS" 2>/dev/null
fi

# Step 3: INJECT WRONG PLACES — personal errand locations
# Home: Memorial City Mall area (29.7744, -95.5560)
# Work: Restaurant in Montrose (29.7455, -95.3937)
sqlite3 "$PLACES_DB" "DELETE FROM place WHERE type=0 OR type=1;" 2>/dev/null
sqlite3 "$PLACES_DB" "INSERT INTO place (type, title, latitude, longitude, address_street, address_city) VALUES (0, 'Memorial Mall', 29.7744, -95.5560, '303 Memorial City Way', 'Houston');" 2>/dev/null
sqlite3 "$PLACES_DB" "INSERT INTO place (type, title, latitude, longitude, address_street, address_city) VALUES (1, 'Underbelly HTX', 29.7455, -95.3937, '1100 Westheimer Rd', 'Houston');" 2>/dev/null

# Step 4: INJECT WRONG ROUTE SETTINGS — commuter preferences
# Shortest route (wrong — field service needs fastest response)
sed -i 's|name="preferenceKey_routePlanning_routeComputing">[^<]*|name="preferenceKey_routePlanning_routeComputing">0|' "$PREFS_FILE"

# Avoid tolls ON (wrong — company pays for tolls to save time)
sed -i 's|name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="true"|' "$PREFS_FILE"

# Highways allowed (correct — keep)
sed -i 's|name="tmp_preferenceKey_routePlanning_highways_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_highways_avoid" value="false"|' "$PREFS_FILE"

# Ferries avoided (correct for Houston — keep)
sed -i 's|name="tmp_preferenceKey_routePlanning_ferries_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_ferries_avoid" value="true"|' "$PREFS_FILE"

# Unpaved avoided (WRONG — utility crew NEEDS unpaved access to remote infrastructure)
sed -i 's|name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="true"|' "$PREFS_FILE"

# Arrive in direction: OFF (should be ON for safe infrastructure access)
sed -i 's|name="preferenceKey_arriveInDrivingSide" value="[^"]*"|name="preferenceKey_arriveInDrivingSide" value="false"|' "$PREFS_FILE"

# Step 5: INJECT WRONG DISPLAY — commuter defaults
sed -i 's|name="preferenceKey_viewAndUnits_distanceUnits">[^<]*|name="preferenceKey_viewAndUnits_distanceUnits">1|' "$PREFS_FILE"
sed -i 's|name="preferenceKey_viewAndUnits_temperatureUnits">[^<]*|name="preferenceKey_viewAndUnits_temperatureUnits">Metric|' "$PREFS_FILE"
sed -i 's|name="preferenceKey_viewAndUnits_timeFormat">[^<]*|name="preferenceKey_viewAndUnits_timeFormat">0|' "$PREFS_FILE"
sed -i 's|name="preferenceKey_viewAndUnits_colorScheme">[^<]*|name="preferenceKey_viewAndUnits_colorScheme">2|' "$PREFS_FILE"
sed -i 's|name="preferenceKey_viewAndUnits_fontSize">[^<]*|name="preferenceKey_viewAndUnits_fontSize">0|' "$PREFS_FILE"
sed -i 's|name="preferenceKey_compass" value="[^"]*"|name="preferenceKey_compass" value="false"|' "$PREFS_FILE"

# Step 6: Record baseline
INITIAL_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" "SELECT COUNT(*) FROM vehicle;" 2>/dev/null || echo "1")
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/utility_initial_vehicle_count

SELECTED_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/utility_initial_selected_id

date +%s > /data/local/tmp/utility_task_start_timestamp

# Step 7: Launch app
input keyevent KEYCODE_HOME
sleep 1

monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

screencap -p /data/local/tmp/task_start_screenshot.png 2>/dev/null

echo "=== restore_utility_crew_field_gps setup complete ==="
