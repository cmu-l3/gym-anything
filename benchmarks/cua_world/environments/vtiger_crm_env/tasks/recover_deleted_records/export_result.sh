#!/bin/bash
echo "=== Exporting recover_deleted_records results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM fallback
take_screenshot /tmp/recover_records_final.png

# Read IDs established during setup
RED_HAT_ID=$(jq -r '.red_hat' /tmp/target_ids.json 2>/dev/null)
SUN_MICRO_ID=$(jq -r '.sun_micro' /tmp/target_ids.json 2>/dev/null)
JIM_ID=$(jq -r '.jim' /tmp/target_ids.json 2>/dev/null)
SCOTT_ID=$(jq -r '.scott' /tmp/target_ids.json 2>/dev/null)

# Query current deleted status of the exact original records
RED_HAT_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid='$RED_HAT_ID'" | tr -d '[:space:]')
SUN_MICRO_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid='$SUN_MICRO_ID'" | tr -d '[:space:]')
JIM_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid='$JIM_ID'" | tr -d '[:space:]')
SCOTT_DELETED=$(vtiger_db_query "SELECT deleted FROM vtiger_crmentity WHERE crmid='$SCOTT_ID'" | tr -d '[:space:]')

# Query if new duplicate records were manually created instead of recovered
NEW_RED_HAT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE label='Red Hat Inc' AND setype='Accounts' AND deleted=0 AND crmid != '$RED_HAT_ID'" | tr -d '[:space:]')
NEW_JIM=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE label='Jim Whitehurst' AND setype='Contacts' AND deleted=0 AND crmid != '$JIM_ID'" | tr -d '[:space:]')

# Query tags associated with the restored Red Hat record
TAGS=$(vtiger_db_query "SELECT ft.tag FROM vtiger_freetags ft INNER JOIN vtiger_freetagged_objects fto ON ft.id = fto.tag_id WHERE fto.object_id = '$RED_HAT_ID'" 2>/dev/null | tr '\n' ' ' | xargs || echo "")

# Fallback: Check standard tags table if freetags is empty
if [ -z "$TAGS" ]; then
    TAGS=$(vtiger_db_query "SELECT tag FROM vtiger_tags WHERE crmid = '$RED_HAT_ID'" 2>/dev/null | tr '\n' ' ' | xargs || echo "")
fi

RESULT_JSON=$(cat << JSONEOF
{
  "red_hat_deleted": "${RED_HAT_DELETED:-1}",
  "sun_micro_deleted": "${SUN_MICRO_DELETED:-1}",
  "jim_deleted": "${JIM_DELETED:-1}",
  "scott_deleted": "${SCOTT_DELETED:-1}",
  "red_hat_tags": "$(json_escape "${TAGS:-}")",
  "red_hat_id": "${RED_HAT_ID}",
  "jim_id": "${JIM_ID}",
  "new_red_hat_count": ${NEW_RED_HAT:-0},
  "new_jim_count": ${NEW_JIM:-0}
}
JSONEOF
)

safe_write_result "/tmp/recover_records_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/recover_records_result.json"
echo "$RESULT_JSON"
echo "=== recover_deleted_records export complete ==="