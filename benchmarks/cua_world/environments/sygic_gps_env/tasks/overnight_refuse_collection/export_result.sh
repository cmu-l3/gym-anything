#!/system/bin/sh
# Post-task export for overnight_refuse_collection.
# Force-stops app to flush prefs, then reads vehicle DB and prefs XML.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting overnight_refuse_collection result ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
RESULT_FILE="/data/local/tmp/overnight_refuse_collection_result.json"

screencap -p /data/local/tmp/overnight_refuse_collection_end_screenshot.png 2>/dev/null
uiautomator dump /sdcard/ui_dump_refuse.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# Read baseline values
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/overnight_refuse_collection_initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/overnight_refuse_collection_initial_selected_id 2>/dev/null || echo "1")

# Query current vehicle count
CURRENT_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle;' 2>/dev/null || echo "0")
CURRENT_VEHICLE_COUNT=${CURRENT_VEHICLE_COUNT:-0}
NEW_VEHICLES=$((CURRENT_VEHICLE_COUNT - INITIAL_VEHICLE_COUNT))

# Query for the refuse truck profile (search by name keywords)
TRUCK_DATA=$(sqlite3 "$VEHICLE_DB" "SELECT id, type, fuelType, name, productionYear, emissionCategory FROM vehicle WHERE name LIKE '%refuse%' OR name LIKE '%Refuse%' OR name LIKE '%truck%' OR name LIKE '%Truck%' OR name LIKE '%waste%' OR name LIKE '%Waste%' ORDER BY id DESC LIMIT 1;" 2>/dev/null)

TRUCK_EXISTS="false"
TRUCK_ID=""
TRUCK_TYPE=""
TRUCK_FUEL=""
TRUCK_NAME=""
TRUCK_YEAR=""
TRUCK_EMISSION=""

if [ -n "$TRUCK_DATA" ]; then
    TRUCK_EXISTS="true"
    TRUCK_ID=$(echo "$TRUCK_DATA" | cut -d'|' -f1)
    TRUCK_TYPE=$(echo "$TRUCK_DATA" | cut -d'|' -f2)
    TRUCK_FUEL=$(echo "$TRUCK_DATA" | cut -d'|' -f3)
    TRUCK_NAME=$(echo "$TRUCK_DATA" | cut -d'|' -f4)
    TRUCK_YEAR=$(echo "$TRUCK_DATA" | cut -d'|' -f5)
    TRUCK_EMISSION=$(echo "$TRUCK_DATA" | cut -d'|' -f6)
fi

# Query selected vehicle profile ID
SELECTED_VEHICLE_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')

# Read preference values
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
AVOID_HIGHWAYS=$(grep 'tmp_preferenceKey_routePlanning_motorways_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
APP_THEME=$(grep 'preferenceKey_app_theme' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
TEMP_UNITS=$(grep 'preferenceKey_weather_temperatureUnits' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

cat > "$RESULT_FILE" << ENDOFRESULT
{
    "initial_vehicle_count": $INITIAL_VEHICLE_COUNT,
    "current_vehicle_count": $CURRENT_VEHICLE_COUNT,
    "new_vehicles": $NEW_VEHICLES,
    "truck_exists": $TRUCK_EXISTS,
    "truck_id": "$TRUCK_ID",
    "truck_type": "$TRUCK_TYPE",
    "truck_fuel": "$TRUCK_FUEL",
    "truck_name": "$TRUCK_NAME",
    "truck_year": "$TRUCK_YEAR",
    "truck_emission": "$TRUCK_EMISSION",
    "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
    "initial_selected_id": "$INITIAL_SELECTED_ID",
    "route_compute": "$ROUTE_COMPUTE",
    "avoid_highways": "$AVOID_HIGHWAYS",
    "app_theme": "$APP_THEME",
    "temperature_units": "$TEMP_UNITS",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat "$RESULT_FILE"
echo "=== Export complete ==="
