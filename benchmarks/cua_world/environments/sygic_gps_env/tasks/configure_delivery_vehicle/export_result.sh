#!/system/bin/sh
# Export script for configure_delivery_vehicle task.
# Queries vehicle database and preferences to verify task completion.

# Ensure root access for reading app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting configure_delivery_vehicle result ==="

PACKAGE="com.sygic.aura"

# Take final screenshot
screencap -p /data/local/tmp/task_end_screenshot.png 2>/dev/null

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Get baseline
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/initial_selected_vehicle_id 2>/dev/null || echo "1")

# Force stop app so DB writes flush
am force-stop $PACKAGE
sleep 2

# Query current vehicle count
CURRENT_VEHICLE_COUNT=$(sqlite3 /data/data/$PACKAGE/databases/vehicles-database 'SELECT COUNT(*) FROM vehicle;' 2>/dev/null || echo "0")
CURRENT_VEHICLE_COUNT=${CURRENT_VEHICLE_COUNT:-0}
INITIAL_VEHICLE_COUNT=${INITIAL_VEHICLE_COUNT:-1}
NEW_VEHICLES=$((CURRENT_VEHICLE_COUNT - INITIAL_VEHICLE_COUNT))

# Query for "Delivery Van" vehicle profile
DELIVERY_VAN_DATA=$(sqlite3 /data/data/$PACKAGE/databases/vehicles-database "SELECT id, type, fuelType, name, productionYear, emissionCategory FROM vehicle WHERE name LIKE '%Delivery%' OR name LIKE '%delivery%' OR name LIKE '%Van%' OR name LIKE '%van%' LIMIT 1;")

DELIVERY_VAN_EXISTS="false"
DV_ID=""
DV_TYPE=""
DV_FUEL=""
DV_NAME=""
DV_YEAR=""
DV_EMISSION=""

if [ -n "$DELIVERY_VAN_DATA" ]; then
    DELIVERY_VAN_EXISTS="true"
    DV_ID=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f1)
    DV_TYPE=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f2)
    DV_FUEL=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f3)
    DV_NAME=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f4)
    DV_YEAR=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f5)
    DV_EMISSION=$(echo "$DELIVERY_VAN_DATA" | cut -d'|' -f6)
fi

# Query selected vehicle profile ID from shared prefs
SELECTED_VEHICLE_ID=$(cat /data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml 2>/dev/null | grep 'selected_vehicle_profile_id' | sed 's/.*value="\([^"]*\)".*/\1/')

# Query route compute preference
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' /data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml | sed 's/.*>\(.*\)<.*/\1/')

# Query toll roads avoidance
AVOID_TOLLS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' /data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml | sed 's/.*value="\([^"]*\)".*/\1/')

# Query arrive in direction
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' /data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml | sed 's/.*value="\([^"]*\)".*/\1/')

# Create result JSON
cat > /data/local/tmp/configure_delivery_vehicle_result.json << ENDOFRESULT
{
    "initial_vehicle_count": $INITIAL_VEHICLE_COUNT,
    "current_vehicle_count": $CURRENT_VEHICLE_COUNT,
    "new_vehicles": $NEW_VEHICLES,
    "delivery_van_exists": $DELIVERY_VAN_EXISTS,
    "delivery_van_id": "$DV_ID",
    "delivery_van_type": "$DV_TYPE",
    "delivery_van_fuel": "$DV_FUEL",
    "delivery_van_name": "$DV_NAME",
    "delivery_van_year": "$DV_YEAR",
    "delivery_van_emission": "$DV_EMISSION",
    "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
    "initial_selected_id": "$INITIAL_SELECTED_ID",
    "route_compute": "$ROUTE_COMPUTE",
    "avoid_tolls": "$AVOID_TOLLS",
    "arrive_in_direction": "$ARRIVE_IN_DIR",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat /data/local/tmp/configure_delivery_vehicle_result.json

echo "=== Export Complete ==="
