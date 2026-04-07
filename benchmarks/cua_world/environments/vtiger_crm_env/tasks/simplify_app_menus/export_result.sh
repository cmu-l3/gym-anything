#!/bin/bash
echo "=== Exporting simplify_app_menus results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query mappings to see if the modules were removed from the specific apps
CAMP_IN_MKT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_app2tab a JOIN vtiger_tab t ON a.tabid = t.tabid WHERE a.appname = 'MARKETING' AND t.name = 'Campaigns'" | tr -d '[:space:]')

PB_IN_INV=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_app2tab a JOIN vtiger_tab t ON a.tabid = t.tabid WHERE a.appname = 'INVENTORY' AND t.name = 'PriceBooks'" | tr -d '[:space:]')

# Check the global presence flag to catch if they just completely disabled the module 
# (which is cheating based on the instructions)
# presence=0 means enabled/visible, presence=1 means completely disabled
CAMP_PRESENCE=$(vtiger_db_query "SELECT presence FROM vtiger_tab WHERE name = 'Campaigns'" | tr -d '[:space:]')
PB_PRESENCE=$(vtiger_db_query "SELECT presence FROM vtiger_tab WHERE name = 'PriceBooks'" | tr -d '[:space:]')

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Prepare JSON result
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START:-0},
  "task_end_time": ${TASK_END:-0},
  "campaigns_in_marketing": ${CAMP_IN_MKT:-0},
  "pricebooks_in_inventory": ${PB_IN_INV:-0},
  "campaigns_presence": ${CAMP_PRESENCE:-0},
  "pricebooks_presence": ${PB_PRESENCE:-0}
}
JSONEOF
)

# Write result securely
safe_write_result "/tmp/simplify_menus_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/simplify_menus_result.json"
cat /tmp/simplify_menus_result.json
echo "=== Export complete ==="