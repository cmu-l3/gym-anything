#!/system/bin/sh
# Post-task export for courier_urban_delivery.
# Force-stops the app so prefs are flushed, then reads vehicle DB and prefs XML.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting courier_urban_delivery result ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
RESULT_FILE="/data/local/tmp/courier_urban_delivery_result.json"

# Take final screenshot
screencap -p /data/local/tmp/courier_urban_delivery_end_screenshot.png 2>/dev/null

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump_courier.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# Read baseline values
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/courier_urban_delivery_initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/courier_urban_delivery_initial_selected_id 2>/dev/null || echo "1")

# Query current vehicle count
CURRENT_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle;' 2>/dev/null || echo "0")
CURRENT_VEHICLE_COUNT=${CURRENT_VEHICLE_COUNT:-0}
NEW_VEHICLES=$((CURRENT_VEHICLE_COUNT - INITIAL_VEHICLE_COUNT))

# Query for the new courier van profile (search by name)
VAN_DATA=$(sqlite3 "$VEHICLE_DB" "SELECT id, type, fuelType, name, productionYear, emissionCategory FROM vehicle WHERE name LIKE '%courier%' OR name LIKE '%Courier%' OR name LIKE '%City%' OR name LIKE '%city%' OR name LIKE '%Van%' OR name LIKE '%van%' ORDER BY id DESC LIMIT 1;" 2>/dev/null)

VAN_EXISTS="false"
VAN_ID=""
VAN_TYPE=""
VAN_FUEL=""
VAN_NAME=""
VAN_YEAR=""
VAN_EMISSION=""

if [ -n "$VAN_DATA" ]; then
    VAN_EXISTS="true"
    VAN_ID=$(echo "$VAN_DATA" | cut -d'|' -f1)
    VAN_TYPE=$(echo "$VAN_DATA" | cut -d'|' -f2)
    VAN_FUEL=$(echo "$VAN_DATA" | cut -d'|' -f3)
    VAN_NAME=$(echo "$VAN_DATA" | cut -d'|' -f4)
    VAN_YEAR=$(echo "$VAN_DATA" | cut -d'|' -f5)
    VAN_EMISSION=$(echo "$VAN_DATA" | cut -d'|' -f6)
fi

# Query selected vehicle profile ID
SELECTED_VEHICLE_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')

# Read preference values
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
AVOID_TOLLS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
DISTANCE_UNITS=$(grep 'preferenceKey_regional_distanceUnitsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')

cat > "$RESULT_FILE" << ENDOFRESULT
{
    "initial_vehicle_count": $INITIAL_VEHICLE_COUNT,
    "current_vehicle_count": $CURRENT_VEHICLE_COUNT,
    "new_vehicles": $NEW_VEHICLES,
    "van_exists": $VAN_EXISTS,
    "van_id": "$VAN_ID",
    "van_type": "$VAN_TYPE",
    "van_fuel": "$VAN_FUEL",
    "van_name": "$VAN_NAME",
    "van_year": "$VAN_YEAR",
    "van_emission": "$VAN_EMISSION",
    "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
    "initial_selected_id": "$INITIAL_SELECTED_ID",
    "route_compute": "$ROUTE_COMPUTE",
    "avoid_tolls": "$AVOID_TOLLS",
    "distance_units": "$DISTANCE_UNITS",
    "arrive_in_direction": "$ARRIVE_IN_DIR",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat "$RESULT_FILE"
echo "=== Export complete ==="
