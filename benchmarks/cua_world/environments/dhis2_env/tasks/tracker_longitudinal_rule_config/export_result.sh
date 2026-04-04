#!/bin/bash
# Export script for Longitudinal Rule Config task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Fallback API function
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")
PROGRAM_ID=$(cat /tmp/target_program_id.txt 2>/dev/null)
DE_ID=$(cat /tmp/target_data_element_id.txt 2>/dev/null)

echo "Collecting metadata for Program: $PROGRAM_ID"

# 1. Get all Program Rule Variables for this program
# We fetch ALL because the agent might have created them without associating strictly to the program initially (though unlikely in UI)
# Filtering by program is safer: filter=program.id:eq:$PROGRAM_ID
echo "Fetching Program Rule Variables..."
VARIABLES_JSON=$(dhis2_api "programRuleVariables?filter=program.id:eq:${PROGRAM_ID}&fields=id,name,programRuleVariableSourceType,dataElement[id,displayName],created&paging=false")

# 2. Get all Program Rules for this program
echo "Fetching Program Rules..."
RULES_JSON=$(dhis2_api "programRules?filter=program.id:eq:${PROGRAM_ID}&fields=id,name,condition,programRuleActions[programRuleActionType,dataElement],created&paging=false")

# Create result JSON
cat > /tmp/longitudinal_rule_result.json << EOF
{
    "task_start_iso": "$TASK_START_ISO",
    "program_id": "$PROGRAM_ID",
    "target_data_element_id": "$DE_ID",
    "variables": $VARIABLES_JSON,
    "rules": $RULES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/longitudinal_rule_result.json

echo "Result saved to /tmp/longitudinal_rule_result.json"
echo "=== Export Complete ==="