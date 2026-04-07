#!/bin/bash
echo "=== Setting up fleet_vehicle_refresh_cycle task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# ---- Dynamic Schema Discovery ----
# Account for slight variations in Sentrifugo schema versions
USER_COL=$(sentrifugo_db_query "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_NAME='main_assetallocations' AND (COLUMN_NAME='user_id' OR COLUMN_NAME='employee_id' OR COLUMN_NAME='allocated_to') LIMIT 1" | tr -d '[:space:]')
[ -z "$USER_COL" ] && USER_COL="user_id"

STATUS_COL=$(sentrifugo_db_query "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_NAME='main_assets' AND (COLUMN_NAME='assetstatus' OR COLUMN_NAME='status') LIMIT 1" | tr -d '[:space:]')
[ -z "$STATUS_COL" ] && STATUS_COL="assetstatus"

# ---- Clean up prior run artifacts ----
log "Cleaning up prior run artifacts..."
sentrifugo_db_root_query "DELETE FROM main_users WHERE employeeId IN ('EMP051', 'EMP052', 'EMP053');" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_assetallocations WHERE asset_id IN (SELECT id FROM main_assets WHERE assetcode LIKE 'TRK-2015-%' OR assetcode LIKE 'EV-%');" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_assets WHERE assetcode LIKE 'TRK-2015-%' OR assetcode LIKE 'EV-%';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_assetcategories WHERE assetgroupname IN ('Site Vehicles', 'Electric Vehicles');" 2>/dev/null || true

# ---- Seed Environment State ----
log "Seeding required initial state..."

# 1. Create the Shift Supervisors
sentrifugo_db_root_query "INSERT INTO main_users (employeeId, firstname, lastname, emailaddress, isactive, userrole_id, userstatus) VALUES ('EMP051', 'Sarah', 'Jenkins', 'sjenkins@greenergy.local', 1, 3, 'old');"
sentrifugo_db_root_query "INSERT INTO main_users (employeeId, firstname, lastname, emailaddress, isactive, userrole_id, userstatus) VALUES ('EMP052', 'Michael', 'Chang', 'mchang@greenergy.local', 1, 3, 'old');"
sentrifugo_db_root_query "INSERT INTO main_users (employeeId, firstname, lastname, emailaddress, isactive, userrole_id, userstatus) VALUES ('EMP053', 'David', 'Rodriguez', 'drodriguez@greenergy.local', 1, 3, 'old');"

# 2. Create the Site Vehicles Category
sentrifugo_db_root_query "INSERT INTO main_assetcategories (assetgroupname, isactive) VALUES ('Site Vehicles', 1);"
SITE_CAT_ID=$(sentrifugo_db_query "SELECT id FROM main_assetcategories WHERE assetgroupname='Site Vehicles' LIMIT 1" | tr -d '[:space:]')

# 3. Create the Legacy TRK Assets
sentrifugo_db_root_query "INSERT INTO main_assets (assetcode, assetname, category_id, serial_number, ${STATUS_COL}, isactive) VALUES ('TRK-2015-A', 'Ford F-150', ${SITE_CAT_ID}, 'VIN-001', 'Working', 1);"
sentrifugo_db_root_query "INSERT INTO main_assets (assetcode, assetname, category_id, serial_number, ${STATUS_COL}, isactive) VALUES ('TRK-2015-B', 'Ford F-150', ${SITE_CAT_ID}, 'VIN-002', 'Working', 1);"
sentrifugo_db_root_query "INSERT INTO main_assets (assetcode, assetname, category_id, serial_number, ${STATUS_COL}, isactive) VALUES ('TRK-2015-C', 'Ford F-150', ${SITE_CAT_ID}, 'VIN-003', 'Working', 1);"

# 4. Allocate Legacy Assets to Supervisors
TRK_A_ID=$(sentrifugo_db_query "SELECT id FROM main_assets WHERE assetcode='TRK-2015-A' LIMIT 1" | tr -d '[:space:]')
TRK_B_ID=$(sentrifugo_db_query "SELECT id FROM main_assets WHERE assetcode='TRK-2015-B' LIMIT 1" | tr -d '[:space:]')
TRK_C_ID=$(sentrifugo_db_query "SELECT id FROM main_assets WHERE assetcode='TRK-2015-C' LIMIT 1" | tr -d '[:space:]')

U1_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP051' LIMIT 1" | tr -d '[:space:]')
U2_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP052' LIMIT 1" | tr -d '[:space:]')
U3_ID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='EMP053' LIMIT 1" | tr -d '[:space:]')

CURRENT_DATE=$(date +%Y-%m-%d)
sentrifugo_db_root_query "INSERT INTO main_assetallocations (asset_id, ${USER_COL}, allocated_date, isactive) VALUES (${TRK_A_ID}, ${U1_ID}, '${CURRENT_DATE}', 1);"
sentrifugo_db_root_query "INSERT INTO main_assetallocations (asset_id, ${USER_COL}, allocated_date, isactive) VALUES (${TRK_B_ID}, ${U2_ID}, '${CURRENT_DATE}', 1);"
sentrifugo_db_root_query "INSERT INTO main_assetallocations (asset_id, ${USER_COL}, allocated_date, isactive) VALUES (${TRK_C_ID}, ${U3_ID}, '${CURRENT_DATE}', 1);"

# ---- Drop directive on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fleet_refresh_directive.txt << 'DIRECTIVE'
===============================================================
GREENERGY BIOMASS CORP — FLEET REFRESH DIRECTIVE
Effective Date: Q1 2026
===============================================================

Our site operations fleet is transitioning to electric vehicles.
Please update the HRMS Assets module with the following changes:

PART 1: NEW CATEGORY
--------------------
Create a new Asset Category named "Electric Vehicles".

PART 2: LEGACY FLEET RETIREMENT
-------------------------------
The following vehicles are being sold for scrap. 
1. Asset Code: TRK-2015-A (Assigned to: Sarah Jenkins)
2. Asset Code: TRK-2015-B (Assigned to: Michael Chang)
3. Asset Code: TRK-2015-C (Assigned to: David Rodriguez)

ACTION REQUIRED: 
- Revoke/Return the asset allocation for all three trucks.
- Edit the asset records and change their Status to "Not Working".
- COMPLIANCE WARNING: Do NOT delete the asset records. We must 
  retain them in the system for historical audit purposes.

PART 3: NEW FLEET PROVISIONING
------------------------------
Create the following new assets under the "Electric Vehicles" category
and allocate them to the corresponding shift supervisors.

Vehicle 1:
- Asset Code: EV-001
- Asset Name: Ford F-150 Lightning
- Serial Number / VIN: 1FTVW1EL3NWG10001
- Allocate To: Sarah Jenkins

Vehicle 2:
- Asset Code: EV-002
- Asset Name: Ford F-150 Lightning
- Serial Number / VIN: 1FTVW1EL3NWG10002
- Allocate To: Michael Chang

Vehicle 3:
- Asset Code: EV-003
- Asset Name: Rivian R1T
- Serial Number / VIN: 7FCTGAAA1NN000003
- Allocate To: David Rodriguez

===============================================================
DIRECTIVE
chown ga:ga /home/ga/Desktop/fleet_refresh_directive.txt
log "Directive file placed on Desktop."

# ---- Navigate to dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready."
echo "=== Setup complete ==="