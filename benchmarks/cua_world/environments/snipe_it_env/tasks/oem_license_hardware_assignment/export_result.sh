#!/bin/bash
echo "=== Exporting oem_license_hardware_assignment results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

REDSHIFT_ID=$(cat /tmp/redshift_id.txt 2>/dev/null)
BMD_ID=$(cat /tmp/bmd_id.txt 2>/dev/null)
ASSET1_ID=$(cat /tmp/asset1_id.txt 2>/dev/null)
ASSET2_ID=$(cat /tmp/asset2_id.txt 2>/dev/null)
ASSET3_ID=$(cat /tmp/asset3_id.txt 2>/dev/null)
ASSET4_ID=$(cat /tmp/asset4_id.txt 2>/dev/null)
SL_RETIRED_ID=$(cat /tmp/sl_retired_id.txt 2>/dev/null)
USER_SEATS_BASELINE=$(cat /tmp/user_seats_baseline.txt 2>/dev/null || echo "0")

# 1. Check DaVinci Resolve License creation
DAVINCI_DATA=$(snipeit_db_query "SELECT id, seats, purchase_cost, manufacturer_id FROM licenses WHERE name='DaVinci Resolve Studio - Node Locked' AND deleted_at IS NULL LIMIT 1")
DAVINCI_FOUND="false"
DAVINCI_ID=""
DAVINCI_SEATS=0
DAVINCI_COST=0
DAVINCI_MFR=""

if [ -n "$DAVINCI_DATA" ]; then
    DAVINCI_FOUND="true"
    DAVINCI_ID=$(echo "$DAVINCI_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    DAVINCI_SEATS=$(echo "$DAVINCI_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    DAVINCI_COST=$(echo "$DAVINCI_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    DAVINCI_MFR=$(echo "$DAVINCI_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
fi

# 2. Check DaVinci Node Assignments
DAVINCI_A1="false"
DAVINCI_A2="false"
DAVINCI_A3="false"
if [ "$DAVINCI_FOUND" = "true" ]; then
    [ $(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$DAVINCI_ID AND asset_id=$ASSET1_ID" | tr -d '[:space:]') -gt 0 ] && DAVINCI_A1="true"
    [ $(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$DAVINCI_ID AND asset_id=$ASSET2_ID" | tr -d '[:space:]') -gt 0 ] && DAVINCI_A2="true"
    [ $(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$DAVINCI_ID AND asset_id=$ASSET3_ID" | tr -d '[:space:]') -gt 0 ] && DAVINCI_A3="true"
fi

# 3. Check Redshift Node Assignments
REDSHIFT_A4_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$REDSHIFT_ID AND asset_id=$ASSET4_ID" | tr -d '[:space:]')
REDSHIFT_A1_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$REDSHIFT_ID AND asset_id=$ASSET1_ID" | tr -d '[:space:]')

# 4. Check Asset 4 Retired status
ASSET4_STATUS=$(snipeit_db_query "SELECT status_id FROM assets WHERE id=$ASSET4_ID" | tr -d '[:space:]')
ASSET4_RETIRED="false"
if [ "$ASSET4_STATUS" = "$SL_RETIRED_ID" ]; then
    ASSET4_RETIRED="true"
fi

# 5. Check anti-gaming
USER_SEATS_CURRENT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE assigned_to IS NOT NULL AND assigned_to > 0" | tr -d '[:space:]')

# Output payload
cat << EOF > /tmp/temp_result.json
{
    "davinci_found": $DAVINCI_FOUND,
    "davinci_seats": "$DAVINCI_SEATS",
    "davinci_cost": "$DAVINCI_COST",
    "davinci_mfr": "$DAVINCI_MFR",
    "expected_bmd_id": "$BMD_ID",
    "davinci_a1": $DAVINCI_A1,
    "davinci_a2": $DAVINCI_A2,
    "davinci_a3": $DAVINCI_A3,
    "redshift_a4_count": ${REDSHIFT_A4_COUNT:-0},
    "redshift_a1_count": ${REDSHIFT_A1_COUNT:-0},
    "asset4_retired": $ASSET4_RETIRED,
    "user_seats_baseline": $USER_SEATS_BASELINE,
    "user_seats_current": ${USER_SEATS_CURRENT:-0}
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat /tmp/temp_result.json)"