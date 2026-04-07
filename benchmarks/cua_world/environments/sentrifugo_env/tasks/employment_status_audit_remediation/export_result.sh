#!/bin/bash
echo "=== Exporting employment_status_audit_remediation result ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_end_screenshot.png

# =====================================================================
# Query Sentrifugo Database for Current State
# =====================================================================

# 1. Extract all active employment status names into a JSON array
STATUSES_RAW=$(sentrifugo_db_query "SELECT workcodename FROM main_employmentstatus WHERE isactive=1;")
STATUSES_JSON="["
FIRST=true
while IFS= read -r line; do
    if [ -n "$line" ]; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            STATUSES_JSON="$STATUSES_JSON,"
        fi
        # Escape quotes to prevent broken JSON
        ESCAPED=$(echo "$line" | sed 's/"/\\"/g' | tr -d '\r')
        STATUSES_JSON="$STATUSES_JSON\"$ESCAPED\""
    fi
done <<< "$STATUSES_RAW"
STATUSES_JSON="$STATUSES_JSON]"

# 2. Extract specific employee employment status assignments
get_emp_status() {
    local empid="$1"
    # Join users with employmentstatus table to get the name of the assigned status
    # Sentrifugo typically uses employementtype, falling back to employeestatus if empty
    local status=$(sentrifugo_db_query "SELECT es.workcodename FROM main_users u JOIN main_employmentstatus es ON u.employementtype = es.id WHERE u.employeeId='${empid}' AND u.isactive=1 LIMIT 1;" | tr -d '\r\n')
    if [ -z "$status" ]; then
        status=$(sentrifugo_db_query "SELECT es.workcodename FROM main_users u JOIN main_employmentstatus es ON u.employeestatus = es.id WHERE u.employeeId='${empid}' AND u.isactive=1 LIMIT 1;" | tr -d '\r\n')
    fi
    echo "$status"
}

EMP005_STATUS=$(get_emp_status "EMP005")
EMP008_STATUS=$(get_emp_status "EMP008")
EMP010_STATUS=$(get_emp_status "EMP010")
EMP014_STATUS=$(get_emp_status "EMP014")
EMP016_STATUS=$(get_emp_status "EMP016")
EMP019_STATUS=$(get_emp_status "EMP019")

# Escape outputs for JSON
E005=$(echo "$EMP005_STATUS" | sed 's/"/\\"/g')
E008=$(echo "$EMP008_STATUS" | sed 's/"/\\"/g')
E010=$(echo "$EMP010_STATUS" | sed 's/"/\\"/g')
E014=$(echo "$EMP014_STATUS" | sed 's/"/\\"/g')
E016=$(echo "$EMP016_STATUS" | sed 's/"/\\"/g')
E019=$(echo "$EMP019_STATUS" | sed 's/"/\\"/g')

# 3. Extract the new leave type
UPL_DATA=$(sentrifugo_db_query "SELECT leavecode, numberofdays FROM main_employeeleavetypes WHERE leavetype='Unpaid Personal Leave' AND isactive=1 LIMIT 1;")
UPL_CODE=$(echo "$UPL_DATA" | cut -f1 | tr -d '\r\n')
UPL_DAYS=$(echo "$UPL_DATA" | cut -f2 | tr -d '\r\n')

# =====================================================================
# Build Export JSON
# =====================================================================

TEMP_JSON=$(mktemp /tmp/audit_remediation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "active_statuses": $STATUSES_JSON,
    "employees": {
        "EMP005": "$E005",
        "EMP008": "$E008",
        "EMP010": "$E010",
        "EMP014": "$E014",
        "EMP016": "$E016",
        "EMP019": "$E019"
    },
    "leave_type": {
        "found": $( [ -n "$UPL_CODE" ] && echo "true" || echo "false" ),
        "code": "$UPL_CODE",
        "days": "$UPL_DAYS"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/audit_remediation_result.json 2>/dev/null || sudo rm -f /tmp/audit_remediation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/audit_remediation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/audit_remediation_result.json
chmod 666 /tmp/audit_remediation_result.json 2>/dev/null || sudo chmod 666 /tmp/audit_remediation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/audit_remediation_result.json"
echo "=== Export Complete ==="