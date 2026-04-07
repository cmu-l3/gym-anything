#!/system/bin/sh
# Post-task export for school_bus_safety_setup.
# Force-stops app to flush prefs, then reads vehicle DB and prefs XML.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting school_bus_safety_setup result ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
RESULT_FILE="/data/local/tmp/school_bus_safety_setup_result.json"

screencap -p /data/local/tmp/school_bus_safety_setup_end_screenshot.png 2>/dev/null
uiautomator dump /sdcard/ui_dump_bus.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# Read baseline values
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/school_bus_safety_setup_initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/school_bus_safety_setup_initial_selected_id 2>/dev/null || echo "1")

# Query current vehicle count
CURRENT_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" 'SELECT COUNT(*) FROM vehicle;' 2>/dev/null || echo "0")
CURRENT_VEHICLE_COUNT=${CURRENT_VEHICLE_COUNT:-0}
NEW_VEHICLES=$((CURRENT_VEHICLE_COUNT - INITIAL_VEHICLE_COUNT))

# Query for the school bus profile (search by name keywords)
BUS_DATA=$(sqlite3 "$VEHICLE_DB" "SELECT id, type, fuelType, name, productionYear, emissionCategory FROM vehicle WHERE name LIKE '%school%' OR name LIKE '%School%' OR name LIKE '%bus%' OR name LIKE '%Bus%' ORDER BY id DESC LIMIT 1;" 2>/dev/null)

BUS_EXISTS="false"
BUS_ID=""
BUS_TYPE=""
BUS_FUEL=""
BUS_NAME=""
BUS_YEAR=""
BUS_EMISSION=""

if [ -n "$BUS_DATA" ]; then
    BUS_EXISTS="true"
    BUS_ID=$(echo "$BUS_DATA" | cut -d'|' -f1)
    BUS_TYPE=$(echo "$BUS_DATA" | cut -d'|' -f2)
    BUS_FUEL=$(echo "$BUS_DATA" | cut -d'|' -f3)
    BUS_NAME=$(echo "$BUS_DATA" | cut -d'|' -f4)
    BUS_YEAR=$(echo "$BUS_DATA" | cut -d'|' -f5)
    BUS_EMISSION=$(echo "$BUS_DATA" | cut -d'|' -f6)
fi

# Query selected vehicle profile ID
SELECTED_VEHICLE_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" | sed 's/.*value="\([^"]*\)".*/\1/')

# Read preference values
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
LANE_GUIDANCE=$(grep 'preferenceKey_navigation_laneGuidance' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_FERRIES=$(grep 'tmp_preferenceKey_routePlanning_ferries_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
DISTANCE_UNITS=$(grep 'preferenceKey_regional_distanceUnitsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

cat > "$RESULT_FILE" << ENDOFRESULT
{
    "initial_vehicle_count": $INITIAL_VEHICLE_COUNT,
    "current_vehicle_count": $CURRENT_VEHICLE_COUNT,
    "new_vehicles": $NEW_VEHICLES,
    "bus_exists": $BUS_EXISTS,
    "bus_id": "$BUS_ID",
    "bus_type": "$BUS_TYPE",
    "bus_fuel": "$BUS_FUEL",
    "bus_name": "$BUS_NAME",
    "bus_year": "$BUS_YEAR",
    "bus_emission": "$BUS_EMISSION",
    "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
    "initial_selected_id": "$INITIAL_SELECTED_ID",
    "arrive_in_direction": "$ARRIVE_IN_DIR",
    "lane_guidance": "$LANE_GUIDANCE",
    "avoid_ferries": "$AVOID_FERRIES",
    "distance_units": "$DISTANCE_UNITS",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat "$RESULT_FILE"
echo "=== Export complete ==="
