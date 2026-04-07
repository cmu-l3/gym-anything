#!/bin/bash
echo "=== Exporting fleet_vehicle_refresh_cycle result ==="

source /workspace/scripts/task_utils.sh

# Dynamic Schema Discovery
USER_COL=$(sentrifugo_db_query "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_NAME='main_assetallocations' AND (COLUMN_NAME='user_id' OR COLUMN_NAME='employee_id' OR COLUMN_NAME='allocated_to') LIMIT 1" | tr -d '[:space:]')
[ -z "$USER_COL" ] && USER_COL="user_id"

STATUS_COL=$(sentrifugo_db_query "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_NAME='main_assets' AND (COLUMN_NAME='assetstatus' OR COLUMN_NAME='status') LIMIT 1" | tr -d '[:space:]')
[ -z "$STATUS_COL" ] && STATUS_COL="assetstatus"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

log "Extracting database state..."

# 1. Category Check
CAT_EV_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assetcategories WHERE assetgroupname='Electric Vehicles'" | tr -d '\n\r')

# 2. Legacy Assets Check
TRK_A_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='TRK-2015-A'" | tr -d '\n\r')
TRK_A_STAT=$(sentrifugo_db_query "SELECT ${STATUS_COL} FROM main_assets WHERE assetcode='TRK-2015-A' LIMIT 1" | tr -d '\n\r"')
TRK_A_ALLOCS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assetallocations a JOIN main_assets t ON a.asset_id = t.id WHERE t.assetcode='TRK-2015-A' AND a.isactive=1 AND (a.return_date IS NULL OR a.return_date='0000-00-00')" | tr -d '\n\r')

TRK_B_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='TRK-2015-B'" | tr -d '\n\r')
TRK_B_STAT=$(sentrifugo_db_query "SELECT ${STATUS_COL} FROM main_assets WHERE assetcode='TRK-2015-B' LIMIT 1" | tr -d '\n\r"')
TRK_B_ALLOCS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assetallocations a JOIN main_assets t ON a.asset_id = t.id WHERE t.assetcode='TRK-2015-B' AND a.isactive=1 AND (a.return_date IS NULL OR a.return_date='0000-00-00')" | tr -d '\n\r')

TRK_C_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='TRK-2015-C'" | tr -d '\n\r')
TRK_C_STAT=$(sentrifugo_db_query "SELECT ${STATUS_COL} FROM main_assets WHERE assetcode='TRK-2015-C' LIMIT 1" | tr -d '\n\r"')
TRK_C_ALLOCS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assetallocations a JOIN main_assets t ON a.asset_id = t.id WHERE t.assetcode='TRK-2015-C' AND a.isactive=1 AND (a.return_date IS NULL OR a.return_date='0000-00-00')" | tr -d '\n\r')

# 3. New EV Assets Check
EV1_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='EV-001'" | tr -d '\n\r')
EV1_CAT=$(sentrifugo_db_query "SELECT c.assetgroupname FROM main_assets a JOIN main_assetcategories c ON a.category_id=c.id WHERE a.assetcode='EV-001' LIMIT 1" | tr -d '\n\r"')
EV1_ALLOC=$(sentrifugo_db_query "SELECT CONCAT(u.firstname, ' ', u.lastname) FROM main_assetallocations a JOIN main_users u ON a.${USER_COL}=u.id JOIN main_assets t ON a.asset_id=t.id WHERE t.assetcode='EV-001' AND (a.isactive=1 OR a.return_date IS NULL) ORDER BY a.id DESC LIMIT 1" | tr -d '\n\r"')

EV2_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='EV-002'" | tr -d '\n\r')
EV2_CAT=$(sentrifugo_db_query "SELECT c.assetgroupname FROM main_assets a JOIN main_assetcategories c ON a.category_id=c.id WHERE a.assetcode='EV-002' LIMIT 1" | tr -d '\n\r"')
EV2_ALLOC=$(sentrifugo_db_query "SELECT CONCAT(u.firstname, ' ', u.lastname) FROM main_assetallocations a JOIN main_users u ON a.${USER_COL}=u.id JOIN main_assets t ON a.asset_id=t.id WHERE t.assetcode='EV-002' AND (a.isactive=1 OR a.return_date IS NULL) ORDER BY a.id DESC LIMIT 1" | tr -d '\n\r"')

EV3_EXISTS=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_assets WHERE assetcode='EV-003'" | tr -d '\n\r')
EV3_CAT=$(sentrifugo_db_query "SELECT c.assetgroupname FROM main_assets a JOIN main_assetcategories c ON a.category_id=c.id WHERE a.assetcode='EV-003' LIMIT 1" | tr -d '\n\r"')
EV3_ALLOC=$(sentrifugo_db_query "SELECT CONCAT(u.firstname, ' ', u.lastname) FROM main_assetallocations a JOIN main_users u ON a.${USER_COL}=u.id JOIN main_assets t ON a.asset_id=t.id WHERE t.assetcode='EV-003' AND (a.isactive=1 OR a.return_date IS NULL) ORDER BY a.id DESC LIMIT 1" | tr -d '\n\r"')

# Create JSON Result Manually to avoid jq dependency
cat > /tmp/task_result.json << EOF
{
  "cat_ev_count": "${CAT_EV_COUNT:-0}",
  "trk_a_exists": "${TRK_A_EXISTS:-0}",
  "trk_a_status": "${TRK_A_STAT}",
  "trk_a_allocs": "${TRK_A_ALLOCS:-0}",
  "trk_b_exists": "${TRK_B_EXISTS:-0}",
  "trk_b_status": "${TRK_B_STAT}",
  "trk_b_allocs": "${TRK_B_ALLOCS:-0}",
  "trk_c_exists": "${TRK_C_EXISTS:-0}",
  "trk_c_status": "${TRK_C_STAT}",
  "trk_c_allocs": "${TRK_C_ALLOCS:-0}",
  "ev_1_exists": "${EV1_EXISTS:-0}",
  "ev_1_cat": "${EV1_CAT}",
  "ev_1_alloc": "${EV1_ALLOC}",
  "ev_2_exists": "${EV2_EXISTS:-0}",
  "ev_2_cat": "${EV2_CAT}",
  "ev_2_alloc": "${EV2_ALLOC}",
  "ev_3_exists": "${EV3_EXISTS:-0}",
  "ev_3_cat": "${EV3_CAT}",
  "ev_3_alloc": "${EV3_ALLOC}"
}
EOF

chmod 666 /tmp/task_result.json
echo "Database state exported."
cat /tmp/task_result.json
echo "=== Export complete ==="