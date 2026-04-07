#!/bin/bash
echo "=== Exporting Picklist Dependency Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the initial max ID tracked during setup
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")

# Retrieve the current max ID
CURRENT_MAX_ID=$(vtiger_db_query "SELECT MAX(id) FROM vtiger_picklist_dependency" | tr -d '[:space:]')
if [ -z "$CURRENT_MAX_ID" ] || [ "$CURRENT_MAX_ID" = "NULL" ]; then
    CURRENT_MAX_ID=0
fi

# Query the exact JSON arrays of target values saved for Education and Technology
EDU_TARGETS=$(vtiger_db_query "SELECT p.targetvalues FROM vtiger_picklist_dependency p JOIN vtiger_tab t ON p.tabid = t.tabid WHERE t.name = 'Leads' AND p.sourcefield = 'industry' AND p.targetfield = 'leadsource' AND p.sourcevalue = 'Education' LIMIT 1")
TECH_TARGETS=$(vtiger_db_query "SELECT p.targetvalues FROM vtiger_picklist_dependency p JOIN vtiger_tab t ON p.tabid = t.tabid WHERE t.name = 'Leads' AND p.sourcefield = 'industry' AND p.targetfield = 'leadsource' AND p.sourcevalue = 'Technology' LIMIT 1")

# Build the JSON output carefully escaping the database payload (which is itself JSON)
RESULT_JSON=$(cat << JSONEOF
{
  "initial_max_id": ${INITIAL_MAX_ID},
  "current_max_id": ${CURRENT_MAX_ID},
  "education_targets": "$(json_escape "${EDU_TARGETS:-}")",
  "technology_targets": "$(json_escape "${TECH_TARGETS:-}")"
}
JSONEOF
)

# Safely write the results payload
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Picklist Dependency Export Complete ==="