#!/bin/bash
echo "=== Exporting helpdesk_break_fix_and_provisioning results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/helpdesk_final.png

source /tmp/task_ids.sh
MAX_ACTION_ID=$(cat /tmp/max_action_id.txt 2>/dev/null || echo "0")

# 1. Gather LAP-DT-01 state
LAP_DT_01_DATA=$(snipeit_db_query "SELECT a.assigned_to, sl.name, a.notes FROM assets a LEFT JOIN status_labels sl ON a.status_id=sl.id WHERE a.id=$LAP_DT_01_ID" 2>/dev/null)
LAP_DT_ASSIGNED=$(echo "$LAP_DT_01_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
LAP_DT_STATUS=$(echo "$LAP_DT_01_DATA" | awk -F'\t' '{print $2}')
LAP_DT_NOTES=$(echo "$LAP_DT_01_DATA" | awk -F'\t' '{print $3}')

# 2. Gather Spare assignments
LAP_SPARE_ASSIGNED=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$LAP_SPARE_01_ID" | tr -d '[:space:]')
MON_SPARE_ASSIGNED=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$MON_SPARE_01_ID" | tr -d '[:space:]')

# 3. Check Action Logs (Anti-gaming check to ensure actions were done in the application UI during the task)
LOG_CHECKIN_LAP_DT=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='checkin' AND item_type='App\\\\Models\\\\Asset' AND item_id=$LAP_DT_01_ID AND id > $MAX_ACTION_ID" | tr -d '[:space:]')
LOG_CHECKOUT_LAP_SPARE=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='checkout' AND item_type='App\\\\Models\\\\Asset' AND item_id=$LAP_SPARE_01_ID AND target_id=$DTAYLOR_ID AND id > $MAX_ACTION_ID" | tr -d '[:space:]')
LOG_CHECKOUT_MON_SPARE=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='checkout' AND item_type='App\\\\Models\\\\Asset' AND item_id=$MON_SPARE_01_ID AND target_id=$MGARCIA_ID AND id > $MAX_ACTION_ID" | tr -d '[:space:]')
LOG_CHECKOUT_ACC=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='checkout' AND item_type='App\\\\Models\\\\Accessory' AND item_id=$ACC_ID AND target_id=$JSMITH_ID AND id > $MAX_ACTION_ID" | tr -d '[:space:]')

# 4. Verify accessory assignment explicitly exists right now
ACC_ASSIGNED=$(snipeit_db_query "SELECT COUNT(*) FROM accessories_users WHERE accessory_id=$ACC_ID AND assigned_to=$JSMITH_ID" | tr -d '[:space:]')

# Format JSON result
RESULT_JSON=$(cat << JSONEOF
{
  "lap_dt_assigned": "${LAP_DT_ASSIGNED}",
  "lap_dt_status": "$(json_escape "$LAP_DT_STATUS")",
  "lap_dt_notes": "$(json_escape "$LAP_DT_NOTES")",
  "lap_spare_assigned": "${LAP_SPARE_ASSIGNED}",
  "mon_spare_assigned": "${MON_SPARE_ASSIGNED}",
  "dtaylor_id": "${DTAYLOR_ID}",
  "mgarcia_id": "${MGARCIA_ID}",
  "jsmith_id": "${JSMITH_ID}",
  "logs": {
    "checkin_lap_dt": ${LOG_CHECKIN_LAP_DT:-0},
    "checkout_lap_spare": ${LOG_CHECKOUT_LAP_SPARE:-0},
    "checkout_mon_spare": ${LOG_CHECKOUT_MON_SPARE:-0},
    "checkout_mouse": ${LOG_CHECKOUT_ACC:-0}
  },
  "acc_assigned": ${ACC_ASSIGNED:-0}
}
JSONEOF
)

safe_write_result "/tmp/helpdesk_task_result.json" "$RESULT_JSON"
echo "Export complete."