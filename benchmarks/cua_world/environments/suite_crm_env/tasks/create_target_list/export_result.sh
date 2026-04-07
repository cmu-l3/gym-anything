#!/bin/bash
set -e
echo "=== Exporting create_target_list results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve Initial and Final counts
INITIAL_COUNT=$(cat /tmp/initial_target_list_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists WHERE deleted=0" | tr -d '[:space:]')

# Fetch the specific Target List data
TL_DATA=$(suitecrm_db_query "SELECT id, name, list_type, description, UNIX_TIMESTAMP(date_entered) FROM prospect_lists WHERE name='Q1 2025 Enterprise Outreach' AND deleted=0 LIMIT 1")

TL_FOUND="false"
TL_ID=""
TL_NAME=""
TL_TYPE=""
TL_DESC=""
TL_TIMESTAMP="0"

if [ -n "$TL_DATA" ]; then
    TL_FOUND="true"
    TL_ID=$(echo "$TL_DATA" | awk -F'\t' '{print $1}')
    TL_NAME=$(echo "$TL_DATA" | awk -F'\t' '{print $2}')
    TL_TYPE=$(echo "$TL_DATA" | awk -F'\t' '{print $3}')
    TL_DESC=$(echo "$TL_DATA" | awk -F'\t' '{print $4}')
    TL_TIMESTAMP=$(echo "$TL_DATA" | awk -F'\t' '{print $5}')
fi

# Check linked contacts
MC_LINKED="false"
DR_LINKED="false"
SW_LINKED="false"

if [ "$TL_FOUND" = "true" ]; then
    # Margaret Chen
    MC_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists_prospects plp JOIN contacts c ON c.id=plp.related_id WHERE plp.prospect_list_id='$TL_ID' AND plp.related_type='Contacts' AND c.first_name='Margaret' AND c.last_name='Chen' AND plp.deleted=0 AND c.deleted=0" | tr -d '[:space:]')
    if [ "$MC_COUNT" -gt 0 ]; then MC_LINKED="true"; fi

    # David Rodriguez
    DR_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists_prospects plp JOIN contacts c ON c.id=plp.related_id WHERE plp.prospect_list_id='$TL_ID' AND plp.related_type='Contacts' AND c.first_name='David' AND c.last_name='Rodriguez' AND plp.deleted=0 AND c.deleted=0" | tr -d '[:space:]')
    if [ "$DR_COUNT" -gt 0 ]; then DR_LINKED="true"; fi

    # Sarah Williams
    SW_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists_prospects plp JOIN contacts c ON c.id=plp.related_id WHERE plp.prospect_list_id='$TL_ID' AND plp.related_type='Contacts' AND c.first_name='Sarah' AND c.last_name='Williams' AND plp.deleted=0 AND c.deleted=0" | tr -d '[:space:]')
    if [ "$SW_COUNT" -gt 0 ]; then SW_LINKED="true"; fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON output via a temporary file safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat << EOF > "$TEMP_JSON"
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "target_list_found": $TL_FOUND,
  "target_list": {
    "id": "$(json_escape "${TL_ID}")",
    "name": "$(json_escape "${TL_NAME}")",
    "type": "$(json_escape "${TL_TYPE}")",
    "description": "$(json_escape "${TL_DESC}")",
    "timestamp": $TL_TIMESTAMP
  },
  "contacts_linked": {
    "margaret_chen": $MC_LINKED,
    "david_rodriguez": $DR_LINKED,
    "sarah_williams": $SW_LINKED
  }
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="