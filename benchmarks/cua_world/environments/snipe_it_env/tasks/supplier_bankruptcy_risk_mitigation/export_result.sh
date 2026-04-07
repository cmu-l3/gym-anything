#!/bin/bash
echo "=== Exporting supplier_bankruptcy_risk_mitigation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Read baseline IDs
APEX_ID=$(cat /tmp/task_apex_id.txt 2>/dev/null || echo "0")
CDW_ID=$(cat /tmp/task_cdw_id.txt 2>/dev/null || echo "0")

# 1. Assess Supplier state (APEX)
APEX_NAME=$(snipeit_db_query "SELECT name FROM suppliers WHERE id=$APEX_ID" | tr -d '\n')
APEX_PHONE=$(snipeit_db_query "SELECT IFNULL(phone, '') FROM suppliers WHERE id=$APEX_ID" | tr -d '\n')
APEX_EMAIL=$(snipeit_db_query "SELECT IFNULL(email, '') FROM suppliers WHERE id=$APEX_ID" | tr -d '\n')
APEX_NOTES=$(snipeit_db_query "SELECT IFNULL(notes, '') FROM suppliers WHERE id=$APEX_ID" | tr -d '\n')

APEX_DELETED_VAL=$(snipeit_db_query "SELECT deleted_at FROM suppliers WHERE id=$APEX_ID" | tr -d '[:space:]')
if [ -n "$APEX_DELETED_VAL" ] && [ "$APEX_DELETED_VAL" != "NULL" ]; then
    APEX_DELETED="true"
else
    APEX_DELETED="false"
fi

# 2. Assess APEX Assets 
# We track these by tag explicitly so we can verify them even if the agent wrongly decoupled their supplier_id
APEX_ASSET_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'APX-%' AND deleted_at IS NULL" | tr -d '[:space:]')
APEX_ASSETS_ZERO_WARRANTY=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'APX-%' AND warranty_months=0 AND deleted_at IS NULL" | tr -d '[:space:]')
APEX_ASSETS_VOID_NOTES=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'APX-%' AND notes LIKE '%[WARRANTY VOID - SUPPLIER BANKRUPT]%' AND deleted_at IS NULL" | tr -d '[:space:]')

# 3. Assess CDW Assets (Collateral Damage check)
CDW_ASSET_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'CDW-%' AND deleted_at IS NULL" | tr -d '[:space:]')
CDW_ASSETS_ZERO_WARRANTY=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'CDW-%' AND warranty_months=0 AND deleted_at IS NULL" | tr -d '[:space:]')
CDW_ASSETS_VOID_NOTES=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag LIKE 'CDW-%' AND notes LIKE '%[WARRANTY VOID - SUPPLIER BANKRUPT]%' AND deleted_at IS NULL" | tr -d '[:space:]')

# Build the result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "apex_id": $APEX_ID,
  "apex_name": "$(json_escape "$APEX_NAME")",
  "apex_phone": "$(json_escape "$APEX_PHONE")",
  "apex_email": "$(json_escape "$APEX_EMAIL")",
  "apex_notes": "$(json_escape "$APEX_NOTES")",
  "apex_deleted": $APEX_DELETED,
  
  "apex_total_assets": ${APEX_ASSET_COUNT:-0},
  "apex_zero_warranty_assets": ${APEX_ASSETS_ZERO_WARRANTY:-0},
  "apex_void_notes_assets": ${APEX_ASSETS_VOID_NOTES:-0},
  
  "cdw_total_assets": ${CDW_ASSET_COUNT:-0},
  "cdw_zero_warranty_assets": ${CDW_ASSETS_ZERO_WARRANTY:-0},
  "cdw_void_notes_assets": ${CDW_ASSETS_VOID_NOTES:-0}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="