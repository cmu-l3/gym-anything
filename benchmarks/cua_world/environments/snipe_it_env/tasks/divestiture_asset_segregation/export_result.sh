#!/bin/bash
echo "=== Exporting divestiture_asset_segregation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to extract entity company_id and updated timestamp
get_entity_json() {
  local table="$1"
  local condition="$2"
  local data=$(snipeit_db_query "SELECT COALESCE(company_id, 0), UNIX_TIMESTAMP(updated_at) FROM $table WHERE $condition LIMIT 1" 2>/dev/null)
  
  if [ -z "$data" ]; then
    echo '{"company_id": 0, "updated_at": 0}'
  else
    local cid=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local uat=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    echo "{\"company_id\": ${cid:-0}, \"updated_at\": ${uat:-0}}"
  fi
}

# 1. Get Company IDs
MEDTECH_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='MedTech Corporation' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MEDTECH_ID" ]; then MEDTECH_ID=0; fi

AURA_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='Aura Health' LIMIT 1" | tr -d '[:space:]')
if [ -z "$AURA_ID" ]; then AURA_ID=0; fi

# 2. Extract Data for Target and Control Entities
DEPT_WEAR=$(get_entity_json "departments" "name='Consumer Wearables'")
DEPT_ENT=$(get_entity_json "departments" "name='Enterprise Health'")

USER_WEAR=$(get_entity_json "users" "username='awearable'")
USER_ENT=$(get_entity_json "users" "username='benterprise'")

ASSET_W1=$(get_entity_json "assets" "asset_tag='AST-W1'")
ASSET_W2=$(get_entity_json "assets" "asset_tag='AST-W2'")

ASSET_E1=$(get_entity_json "assets" "asset_tag='AST-E1'")
ASSET_E2=$(get_entity_json "assets" "asset_tag='AST-E2'")

# Build Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "medtech_id": $MEDTECH_ID,
  "aura_id": $AURA_ID,
  "dept_wearable": $DEPT_WEAR,
  "dept_enterprise": $DEPT_ENT,
  "user_wearable": $USER_WEAR,
  "user_enterprise": $USER_ENT,
  "asset_w1": $ASSET_W1,
  "asset_w2": $ASSET_W2,
  "asset_e1": $ASSET_E1,
  "asset_e2": $ASSET_E2
}
JSONEOF
)

# Save to expected location
safe_write_result "/tmp/divestiture_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/divestiture_result.json"
echo "$RESULT_JSON"
echo "=== divestiture_asset_segregation export complete ==="