#!/system/bin/sh
# Setup script for ngo_supply_convoy_setup task.
# Pattern: Error injection — seeds a personal car profile with wrong routing prefs.
# Agent must: replace vehicle, fix route settings, plan multi-stop route, add on-route gas.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up ngo_supply_convoy_setup task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
BASE_PREFS="/data/data/$PACKAGE/shared_prefs/base_persistence_preferences.xml"
VEHICLE_DB="/data/data/$PACKAGE/databases/vehicles-database"

# Step 1: Force stop app for clean state
am force-stop $PACKAGE
sleep 2

# Step 2: Delete stale output files BEFORE recording timestamp
rm -f /data/local/tmp/ngo_supply_convoy_setup_result.json
rm -f /data/local/tmp/ngo_end_screenshot.png
rm -f /data/local/tmp/ngo_start_screenshot.png
rm -f /sdcard/ngo_ui_dump.xml

# Step 3: Clean up vehicle profiles from prior runs
sqlite3 "$VEHICLE_DB" "DELETE FROM vehicle WHERE name LIKE '%Supply%' OR name LIKE '%supply%' \
  OR name LIKE '%Truck%' OR name LIKE '%truck%' \
  OR name LIKE '%Sedan%' OR name LIKE '%sedan%' \
  OR name LIKE '%Personal%' OR name LIKE '%personal%' \
  OR name LIKE '%NGO%' OR name LIKE '%ngo%';" 2>/dev/null

# Step 4: Inject WRONG vehicle — personal sedan
# Must provide all NOT NULL columns (schema requires batteryCapacityKwh, weightInKg,
# maxChargingPowerKw, supportedConnectorTypes, consumptionAverageKwhPerKm, maxSpeedKmh,
# totalWeightInKg, totalLengthInMm, widthInMm, heightInMm, trailer, propane).
sqlite3 "$VEHICLE_DB" "INSERT INTO vehicle (type, fuelType, name, productionYear, emissionCategory, \
  batteryCapacityKwh, weightInKg, maxChargingPowerKw, supportedConnectorTypes, \
  consumptionAverageKwhPerKm, maxSpeedKmh, totalWeightInKg, totalLengthInMm, \
  widthInMm, heightInMm, trailer, propane) \
  VALUES ('CAR', 'GAS', 'Personal Sedan', 2024, 'EURO6', \
  0.0, 0, 0, '', 0.0, 180.0, 0, 0, 0, 0, 0, 0);" 2>/dev/null

WRONG_VEH_ID=$(sqlite3 "$VEHICLE_DB" "SELECT id FROM vehicle WHERE name='Personal Sedan' LIMIT 1;" 2>/dev/null)
if [ -n "$WRONG_VEH_ID" ]; then
    sed -i "s|name=\"selected_vehicle_profile_id\" value=\"[^\"]*\"|name=\"selected_vehicle_profile_id\" value=\"$WRONG_VEH_ID\"|" "$BASE_PREFS" 2>/dev/null
fi

# Step 5: Inject WRONG route settings
# Fastest (wrong — should be Shortest=0 for delivery efficiency)
sed -i 's|name="preferenceKey_routePlanning_routeComputing">[^<]*|name="preferenceKey_routePlanning_routeComputing">1|' "$PREFS_FILE"

# Avoid unpaved ON (wrong — truck needs unpaved access for field delivery sites)
sed -i 's|name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_unpavedRoads_avoid" value="true"|' "$PREFS_FILE"

# Ferries NOT avoided (wrong — should be true, no ferries needed in Afghanistan)
sed -i 's|name="tmp_preferenceKey_routePlanning_ferries_avoid" value="[^"]*"|name="tmp_preferenceKey_routePlanning_ferries_avoid" value="false"|' "$PREFS_FILE"

# Arrive-in-direction OFF (wrong — should be true for safe delivery stops)
sed -i 's|name="preferenceKey_arriveInDrivingSide" value="[^"]*"|name="preferenceKey_arriveInDrivingSide" value="false"|' "$PREFS_FILE"

# Step 6: Record baselines
INITIAL_VEHICLE_COUNT=$(sqlite3 "$VEHICLE_DB" "SELECT COUNT(*) FROM vehicle;" 2>/dev/null || echo "1")
echo "$INITIAL_VEHICLE_COUNT" > /data/local/tmp/ngo_initial_vehicle_count

SELECTED_ID=$(grep 'selected_vehicle_profile_id' "$BASE_PREFS" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
echo "$SELECTED_ID" > /data/local/tmp/ngo_initial_selected_id

# Record timestamp AFTER deleting stale outputs
date +%s > /data/local/tmp/ngo_task_start_ts

# Step 7: Launch app
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

screencap -p /data/local/tmp/ngo_start_screenshot.png 2>/dev/null

echo "=== ngo_supply_convoy_setup setup complete ==="
