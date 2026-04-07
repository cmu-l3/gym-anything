#!/system/bin/sh
# Export script for restore_utility_crew_field_gps task.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting restore_utility_crew_field_gps result ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PLACES_DB="/data/data/$PACKAGE/databases/places-database"
RESULT_FILE="/data/local/tmp/restore_utility_crew_field_gps_result.json"

screencap -p /data/local/tmp/task_end_screenshot.png 2>/dev/null

am force-stop $PACKAGE
sleep 3

# Baselines
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/utility_initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/utility_initial_selected_id 2>/dev/null || echo "")

# Active vehicle
SELECTED_VEHICLE_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')

ACTIVE_DATA=$(sqlite3 "$VEHICLE_DB" "SELECT id, type, fuelType, name, productionYear, emissionCategory, maxSpeedKmh FROM vehicle WHERE id='$SELECTED_VEHICLE_ID' LIMIT 1;" 2>/dev/null)

AV_TYPE=""
AV_FUEL=""
AV_NAME=""
AV_SPEED="0"

if [ -n "$ACTIVE_DATA" ]; then
    AV_TYPE=$(echo "$ACTIVE_DATA" | cut -d'|' -f2)
    AV_FUEL=$(echo "$ACTIVE_DATA" | cut -d'|' -f3)
    AV_NAME=$(echo "$ACTIVE_DATA" | cut -d'|' -f4)
    AV_SPEED=$(echo "$ACTIVE_DATA" | cut -d'|' -f7)
fi

# Check if wrong vehicle unchanged
WRONG_UNCHANGED="false"
WC=$(sqlite3 "$VEHICLE_DB" "SELECT COUNT(*) FROM vehicle WHERE name='Office Commuter' AND type='CAR';" 2>/dev/null || echo "0")
[ "$WC" -gt 0 ] 2>/dev/null && WRONG_UNCHANGED="true"

# Route settings
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')
AVOID_TOLLS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_HIGHWAYS=$(grep 'tmp_preferenceKey_routePlanning_highways_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_FERRIES=$(grep 'tmp_preferenceKey_routePlanning_ferries_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_UNPAVED=$(grep 'tmp_preferenceKey_routePlanning_unpavedRoads_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')

# Display
DISTANCE_UNITS=$(grep 'preferenceKey_viewAndUnits_distanceUnits' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')
TEMP_UNITS=$(grep 'preferenceKey_viewAndUnits_temperatureUnits' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')
TIME_FORMAT=$(grep 'preferenceKey_viewAndUnits_timeFormat' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')
COLOR_SCHEME=$(grep 'preferenceKey_viewAndUnits_colorScheme' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')

# Places
HOME_ROW=$(sqlite3 "$PLACES_DB" "SELECT id, title, latitude, longitude, address_city FROM place WHERE type=0 LIMIT 1;" 2>/dev/null)
WORK_ROW=$(sqlite3 "$PLACES_DB" "SELECT id, title, latitude, longitude, address_city FROM place WHERE type=1 LIMIT 1;" 2>/dev/null)

if [ -n "$HOME_ROW" ]; then
    H_LAT=$(echo "$HOME_ROW" | cut -d'|' -f3)
    H_LON=$(echo "$HOME_ROW" | cut -d'|' -f4)
    H_CITY=$(echo "$HOME_ROW" | cut -d'|' -f5)
    [ -z "$H_LAT" ] && H_LAT="0"
    [ -z "$H_LON" ] && H_LON="0"
    HOME_JSON="{\"latitude\": $H_LAT, \"longitude\": $H_LON, \"city\": \"$H_CITY\"}"
else
    HOME_JSON="null"
fi

if [ -n "$WORK_ROW" ]; then
    W_LAT=$(echo "$WORK_ROW" | cut -d'|' -f3)
    W_LON=$(echo "$WORK_ROW" | cut -d'|' -f4)
    W_CITY=$(echo "$WORK_ROW" | cut -d'|' -f5)
    [ -z "$W_LAT" ] && W_LAT="0"
    [ -z "$W_LON" ] && W_LON="0"
    WORK_JSON="{\"latitude\": $W_LAT, \"longitude\": $W_LON, \"city\": \"$W_CITY\"}"
else
    WORK_JSON="null"
fi

# Defaults
[ -z "$ROUTE_COMPUTE" ] && ROUTE_COMPUTE="0"
[ -z "$AVOID_TOLLS" ] && AVOID_TOLLS="true"
[ -z "$AVOID_HIGHWAYS" ] && AVOID_HIGHWAYS="false"
[ -z "$AVOID_FERRIES" ] && AVOID_FERRIES="true"
[ -z "$AVOID_UNPAVED" ] && AVOID_UNPAVED="true"
[ -z "$ARRIVE_IN_DIR" ] && ARRIVE_IN_DIR="false"
[ -z "$DISTANCE_UNITS" ] && DISTANCE_UNITS="1"
[ -z "$TEMP_UNITS" ] && TEMP_UNITS="Metric"
[ -z "$TIME_FORMAT" ] && TIME_FORMAT="0"
[ -z "$COLOR_SCHEME" ] && COLOR_SCHEME="2"
[ -z "$AV_SPEED" ] && AV_SPEED="0"

cat > "$RESULT_FILE" << ENDJSON
{
  "active_vehicle_type": "$AV_TYPE",
  "active_vehicle_fuel": "$AV_FUEL",
  "active_vehicle_name": "$AV_NAME",
  "active_vehicle_speed": $AV_SPEED,
  "wrong_vehicle_unchanged": $WRONG_UNCHANGED,
  "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
  "initial_selected_id": "$INITIAL_SELECTED_ID",
  "route_compute": "$ROUTE_COMPUTE",
  "avoid_tolls": "$AVOID_TOLLS",
  "avoid_highways": "$AVOID_HIGHWAYS",
  "avoid_ferries": "$AVOID_FERRIES",
  "avoid_unpaved": "$AVOID_UNPAVED",
  "arrive_in_direction": "$ARRIVE_IN_DIR",
  "home": $HOME_JSON,
  "work": $WORK_JSON,
  "distance_units": "$DISTANCE_UNITS",
  "temperature_units": "$TEMP_UNITS",
  "time_format": "$TIME_FORMAT",
  "color_scheme": "$COLOR_SCHEME",
  "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="
