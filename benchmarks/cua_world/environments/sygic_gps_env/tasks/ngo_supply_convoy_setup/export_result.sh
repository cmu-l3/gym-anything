#!/system/bin/sh
# Post-task export for ngo_supply_convoy_setup.
# Captures: vehicle DB state, route prefs, screenshots, UI dump.
# Route/POI verification is done via VLM on trajectory screenshots.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting ngo_supply_convoy_setup result ==="

PACKAGE="com.sygic.aura"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
RESULT_FILE="/data/local/tmp/ngo_supply_convoy_setup_result.json"

# Take final screenshot (for VLM route/POI verification)
screencap -p /data/local/tmp/ngo_end_screenshot.png 2>/dev/null

# Dump UI hierarchy
uiautomator dump /sdcard/ngo_ui_dump.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 3

# ---- Read baselines ----
INITIAL_VEHICLE_COUNT=$(cat /data/local/tmp/ngo_initial_vehicle_count 2>/dev/null || echo "1")
INITIAL_SELECTED_ID=$(cat /data/local/tmp/ngo_initial_selected_id 2>/dev/null || echo "")

# ---- Vehicle data ----
CURRENT_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" "SELECT COUNT(*) FROM vehicle;" 2>/dev/null || echo "0")
CURRENT_VEHICLE_COUNT=${CURRENT_VEHICLE_COUNT:-0}
NEW_VEHICLES=$((CURRENT_VEHICLE_COUNT - INITIAL_VEHICLE_COUNT))

# Look for the new supply vehicle profile (search by name keywords or by DIESEL fuel)
TRUCK_DATA=$(sqlite3 "$VEHICLE_DB" "SELECT id, type, fuelType, name, productionYear, emissionCategory, maxSpeedKmh \
  FROM vehicle WHERE name LIKE '%Supply%' OR name LIKE '%supply%' \
  OR name LIKE '%Vehicle%' OR name LIKE '%vehicle%' \
  OR name LIKE '%Truck%' OR name LIKE '%truck%' \
  OR (fuelType='DIESEL' AND name != 'Personal Sedan' AND name != 'Vehicle 1') \
  ORDER BY id DESC LIMIT 1;" 2>/dev/null)

TRUCK_EXISTS="false"
TRUCK_ID=""
TRUCK_TYPE=""
TRUCK_FUEL=""
TRUCK_NAME=""
TRUCK_YEAR=""
TRUCK_EMISSION=""
TRUCK_SPEED="0"

if [ -n "$TRUCK_DATA" ]; then
    TRUCK_EXISTS="true"
    TRUCK_ID=$(echo "$TRUCK_DATA" | cut -d'|' -f1)
    TRUCK_TYPE=$(echo "$TRUCK_DATA" | cut -d'|' -f2)
    TRUCK_FUEL=$(echo "$TRUCK_DATA" | cut -d'|' -f3)
    TRUCK_NAME=$(echo "$TRUCK_DATA" | cut -d'|' -f4)
    TRUCK_YEAR=$(echo "$TRUCK_DATA" | cut -d'|' -f5)
    TRUCK_EMISSION=$(echo "$TRUCK_DATA" | cut -d'|' -f6)
    TRUCK_SPEED=$(echo "$TRUCK_DATA" | cut -d'|' -f7)
fi

# Check if the wrong vehicle is still unchanged
WRONG_UNCHANGED="false"
WC=$(sqlite3 "$VEHICLE_DB" "SELECT COUNT(*) FROM vehicle WHERE name='Personal Sedan' AND type='CAR';" 2>/dev/null || echo "0")
[ "$WC" -gt 0 ] 2>/dev/null && WRONG_UNCHANGED="true"

# Query selected vehicle profile ID
SELECTED_VEHICLE_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')

# ---- Route settings ----
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\([^<]*\)<.*/\1/')
AVOID_UNPAVED=$(grep 'tmp_preferenceKey_routePlanning_unpavedRoads_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_FERRIES=$(grep 'tmp_preferenceKey_routePlanning_ferries_avoid' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')

# ---- Defaults for missing values ----
[ -z "$ROUTE_COMPUTE" ] && ROUTE_COMPUTE="1"
[ -z "$AVOID_UNPAVED" ] && AVOID_UNPAVED="true"
[ -z "$AVOID_FERRIES" ] && AVOID_FERRIES="false"
[ -z "$ARRIVE_IN_DIR" ] && ARRIVE_IN_DIR="false"
[ -z "$TRUCK_SPEED" ] && TRUCK_SPEED="0"
[ -z "$SELECTED_VEHICLE_ID" ] && SELECTED_VEHICLE_ID=""

# ---- App running check ----
APP_RUNNING="false"
if dumpsys activity activities 2>/dev/null | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# ---- Write result JSON ----
cat > "$RESULT_FILE" << ENDJSON
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
  "truck_speed": $TRUCK_SPEED,
  "wrong_vehicle_unchanged": $WRONG_UNCHANGED,
  "selected_vehicle_id": "$SELECTED_VEHICLE_ID",
  "initial_selected_id": "$INITIAL_SELECTED_ID",
  "route_compute": "$ROUTE_COMPUTE",
  "avoid_unpaved": "$AVOID_UNPAVED",
  "avoid_ferries": "$AVOID_FERRIES",
  "arrive_in_direction": "$ARRIVE_IN_DIR",
  "app_running": $APP_RUNNING,
  "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== ngo_supply_convoy_setup export complete ==="
