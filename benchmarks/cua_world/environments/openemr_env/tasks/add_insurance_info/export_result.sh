#!/bin/bash
# Export script for Add Insurance Info task

echo "=== Exporting Add Insurance Info Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=5

# Get timing data
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_INS_COUNT=$(cat /tmp/initial_insurance_count 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_total_insurance_count 2>/dev/null || echo "0")

# Get current insurance count for patient
CURRENT_INS_COUNT=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM insurance_data" 2>/dev/null || echo "0")

echo "Insurance count for patient: initial=$INITIAL_INS_COUNT, current=$CURRENT_INS_COUNT"
echo "Total insurance records: initial=$INITIAL_TOTAL_COUNT, current=$CURRENT_TOTAL_COUNT"

# Query for insurance records for this patient
echo ""
echo "=== Querying insurance_data for patient PID=$PATIENT_PID ==="
ALL_INS=$(openemr_query "SELECT id, pid, type, provider, plan_name, policy_number, group_number, subscriber_relationship, subscriber_fname, subscriber_lname, date FROM insurance_data WHERE pid=$PATIENT_PID ORDER BY id DESC" 2>/dev/null)
echo "All insurance records for patient:"
echo "$ALL_INS"

# Query insurance companies to find matching company
echo ""
echo "=== Checking insurance_companies table ==="
INS_COMPANIES=$(openemr_query "SELECT id, name FROM insurance_companies WHERE name LIKE '%Blue%' OR name LIKE '%BCBS%' LIMIT 5" 2>/dev/null)
echo "Matching insurance companies:"
echo "$INS_COMPANIES"

# Get the primary insurance record (most recent)
PRIMARY_INS=$(openemr_query "SELECT id, pid, type, provider, plan_name, policy_number, group_number, subscriber_relationship, subscriber_fname, subscriber_lname, date FROM insurance_data WHERE pid=$PATIENT_PID AND type='primary' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# If no primary found, get any insurance record
if [ -z "$PRIMARY_INS" ]; then
    echo "No primary insurance found, checking for any insurance type..."
    PRIMARY_INS=$(openemr_query "SELECT id, pid, type, provider, plan_name, policy_number, group_number, subscriber_relationship, subscriber_fname, subscriber_lname, date FROM insurance_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Parse insurance data
INS_FOUND="false"
INS_ID=""
INS_TYPE=""
INS_PROVIDER_ID=""
INS_PLAN_NAME=""
INS_POLICY_NUMBER=""
INS_GROUP_NUMBER=""
INS_SUBSCRIBER_REL=""
INS_SUBSCRIBER_FNAME=""
INS_SUBSCRIBER_LNAME=""
INS_EFFECTIVE_DATE=""
INS_COMPANY_NAME=""

if [ -n "$PRIMARY_INS" ]; then
    INS_FOUND="true"
    INS_ID=$(echo "$PRIMARY_INS" | cut -f1)
    INS_PID=$(echo "$PRIMARY_INS" | cut -f2)
    INS_TYPE=$(echo "$PRIMARY_INS" | cut -f3)
    INS_PROVIDER_ID=$(echo "$PRIMARY_INS" | cut -f4)
    INS_PLAN_NAME=$(echo "$PRIMARY_INS" | cut -f5)
    INS_POLICY_NUMBER=$(echo "$PRIMARY_INS" | cut -f6)
    INS_GROUP_NUMBER=$(echo "$PRIMARY_INS" | cut -f7)
    INS_SUBSCRIBER_REL=$(echo "$PRIMARY_INS" | cut -f8)
    INS_SUBSCRIBER_FNAME=$(echo "$PRIMARY_INS" | cut -f9)
    INS_SUBSCRIBER_LNAME=$(echo "$PRIMARY_INS" | cut -f10)
    INS_EFFECTIVE_DATE=$(echo "$PRIMARY_INS" | cut -f11)
    
    # Get insurance company name from provider ID
    if [ -n "$INS_PROVIDER_ID" ] && [ "$INS_PROVIDER_ID" != "NULL" ] && [ "$INS_PROVIDER_ID" != "0" ]; then
        INS_COMPANY_NAME=$(openemr_query "SELECT name FROM insurance_companies WHERE id=$INS_PROVIDER_ID" 2>/dev/null || echo "")
    fi
    
    echo ""
    echo "Insurance record found:"
    echo "  ID: $INS_ID"
    echo "  Type: $INS_TYPE"
    echo "  Provider ID: $INS_PROVIDER_ID"
    echo "  Company Name: $INS_COMPANY_NAME"
    echo "  Plan Name: $INS_PLAN_NAME"
    echo "  Policy Number: $INS_POLICY_NUMBER"
    echo "  Group Number: $INS_GROUP_NUMBER"
    echo "  Subscriber Relationship: $INS_SUBSCRIBER_REL"
    echo "  Effective Date: $INS_EFFECTIVE_DATE"
else
    echo "No insurance record found for patient"
fi

# Check if record was newly created (count increased)
NEW_RECORD_CREATED="false"
if [ "$CURRENT_INS_COUNT" -gt "$INITIAL_INS_COUNT" ]; then
    NEW_RECORD_CREATED="true"
    echo "New insurance record was created during task"
fi

# Validate policy number
POLICY_VALID="false"
if [ "$INS_POLICY_NUMBER" = "XWP845621379" ]; then
    POLICY_VALID="true"
    echo "Policy number matches expected value"
else
    echo "Policy number does not match: expected 'XWP845621379', got '$INS_POLICY_NUMBER'"
fi

# Validate group number
GROUP_VALID="false"
if [ "$INS_GROUP_NUMBER" = "GRP7845210" ]; then
    GROUP_VALID="true"
    echo "Group number matches expected value"
else
    echo "Group number does not match: expected 'GRP7845210', got '$INS_GROUP_NUMBER'"
fi

# Validate insurance company (check if Blue Cross is in the name)
COMPANY_VALID="false"
COMPANY_LOWER=$(echo "$INS_COMPANY_NAME" | tr '[:upper:]' '[:lower:]')
if echo "$COMPANY_LOWER" | grep -qE "(blue cross|blue shield|bcbs)"; then
    COMPANY_VALID="true"
    echo "Insurance company contains Blue Cross/Blue Shield"
fi

# Validate subscriber relationship
SUBSCRIBER_VALID="false"
SUBSCRIBER_LOWER=$(echo "$INS_SUBSCRIBER_REL" | tr '[:upper:]' '[:lower:]')
if echo "$SUBSCRIBER_LOWER" | grep -qE "(self|patient|18)"; then
    SUBSCRIBER_VALID="true"
    echo "Subscriber relationship indicates self/patient"
fi

# Escape special characters for JSON
INS_PLAN_NAME_ESCAPED=$(echo "$INS_PLAN_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
INS_COMPANY_NAME_ESCAPED=$(echo "$INS_COMPANY_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/insurance_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_insurance_count": ${INITIAL_INS_COUNT:-0},
    "current_insurance_count": ${CURRENT_INS_COUNT:-0},
    "insurance_record_found": $INS_FOUND,
    "new_record_created": $NEW_RECORD_CREATED,
    "insurance": {
        "id": "$INS_ID",
        "type": "$INS_TYPE",
        "provider_id": "$INS_PROVIDER_ID",
        "company_name": "$INS_COMPANY_NAME_ESCAPED",
        "plan_name": "$INS_PLAN_NAME_ESCAPED",
        "policy_number": "$INS_POLICY_NUMBER",
        "group_number": "$INS_GROUP_NUMBER",
        "subscriber_relationship": "$INS_SUBSCRIBER_REL",
        "subscriber_fname": "$INS_SUBSCRIBER_FNAME",
        "subscriber_lname": "$INS_SUBSCRIBER_LNAME",
        "effective_date": "$INS_EFFECTIVE_DATE"
    },
    "validation": {
        "policy_number_valid": $POLICY_VALID,
        "group_number_valid": $GROUP_VALID,
        "company_valid": $COMPANY_VALID,
        "subscriber_valid": $SUBSCRIBER_VALID
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/add_insurance_result.json 2>/dev/null || sudo rm -f /tmp/add_insurance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_insurance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_insurance_result.json
chmod 666 /tmp/add_insurance_result.json 2>/dev/null || sudo chmod 666 /tmp/add_insurance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_insurance_result.json"
cat /tmp/add_insurance_result.json

echo ""
echo "=== Export Complete ==="