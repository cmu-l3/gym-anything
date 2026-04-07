#!/bin/bash
echo "=== Exporting helpdesk_request_fulfillment results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read baseline IDs
USER_SJ_ID=$(cat /tmp/user_sj.txt 2>/dev/null || echo "0")
USER_DC_ID=$(cat /tmp/user_dc.txt 2>/dev/null || echo "0")
USER_MG_ID=$(cat /tmp/user_mg.txt 2>/dev/null || echo "0")
USER_RT_ID=$(cat /tmp/user_rt.txt 2>/dev/null || echo "0")
USER_JS_ID=$(cat /tmp/user_js.txt 2>/dev/null || echo "0")

# Verify Asset Checkouts (using DB)
LPT_ASSIGNED=$(snipeit_db_query "SELECT COALESCE(assigned_to, 0) FROM assets WHERE asset_tag='LPT-8001' AND assigned_type LIKE '%User%' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -z "$LPT_ASSIGNED" ]; then LPT_ASSIGNED="0"; fi

MON_ASSIGNED=$(snipeit_db_query "SELECT COALESCE(assigned_to, 0) FROM assets WHERE asset_tag='MON-8002' AND assigned_type LIKE '%User%' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -z "$MON_ASSIGNED" ]; then MON_ASSIGNED="0"; fi

# Verify Accessory and Consumable Checkouts (using API)
if [ "$USER_MG_ID" != "0" ]; then
    USER_MG_ACC_TOTAL=$(snipeit_api GET "users/${USER_MG_ID}/accessories" | jq -r '.total // 0' 2>/dev/null || echo "0")
else
    USER_MG_ACC_TOTAL="0"
fi

if [ "$USER_RT_ID" != "0" ]; then
    USER_RT_CON_TOTAL=$(snipeit_api GET "users/${USER_RT_ID}/consumables" | jq -r '.total // 0' 2>/dev/null || echo "0")
else
    USER_RT_CON_TOTAL="0"
fi

# Verify James Smith has 0 items
if [ "$USER_JS_ID" != "0" ]; then
    JS_ASSETS=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE assigned_to=$USER_JS_ID AND assigned_type LIKE '%User%' AND deleted_at IS NULL" | tr -d '[:space:]')
    JS_ACC=$(snipeit_api GET "users/${USER_JS_ID}/accessories" | jq -r '.total // 0' 2>/dev/null || echo "0")
    JS_CON=$(snipeit_api GET "users/${USER_JS_ID}/consumables" | jq -r '.total // 0' 2>/dev/null || echo "0")
    if [ -z "$JS_ASSETS" ]; then JS_ASSETS=0; fi
    JS_TOTAL=$((JS_ASSETS + JS_ACC + JS_CON))
else
    JS_TOTAL=0
fi

# Check remaining pending requests
PENDING_REQUESTS=$(snipeit_db_query "SELECT COUNT(*) FROM checkout_requests WHERE deleted_at IS NULL AND canceled_at IS NULL AND fulfilled_at IS NULL" | tr -d '[:space:]')
if [ -z "$PENDING_REQUESTS" ]; then PENDING_REQUESTS=0; fi

# Build JSON payload
RESULT_JSON=$(cat << JSONEOF
{
  "lpt_assigned_to": "${LPT_ASSIGNED}",
  "mon_assigned_to": "${MON_ASSIGNED}",
  "user_sj_id": "${USER_SJ_ID}",
  "user_dc_id": "${USER_DC_ID}",
  "user_mg_acc_total": ${USER_MG_ACC_TOTAL},
  "user_rt_con_total": ${USER_RT_CON_TOTAL},
  "js_total_items": ${JS_TOTAL},
  "pending_requests": ${PENDING_REQUESTS}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="