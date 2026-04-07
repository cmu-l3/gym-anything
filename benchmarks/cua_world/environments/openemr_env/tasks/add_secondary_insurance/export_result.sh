#!/bin/bash
# Export script for Add Secondary Insurance task

echo "=== Exporting Add Secondary Insurance Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=6
EXPECTED_POLICY="SEC-2024-889712"
EXPECTED_GROUP="MEDIGAP-F"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial counts
INITIAL_PRIMARY=$(cat /tmp/initial_primary_count.txt 2>/dev/null || echo "0")
INITIAL_SECONDARY=$(cat /tmp/initial_secondary_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL=$(cat /tmp/initial_total_insurance_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_PRIMARY=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID AND type='primary'" 2>/dev/null || echo "0")
CURRENT_SECONDARY=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID AND type='secondary'" 2>/dev/null || echo "0")
CURRENT_TOTAL=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Insurance counts:"
echo "  Primary: $INITIAL_PRIMARY -> $CURRENT_PRIMARY"
echo "  Secondary: $INITIAL_SECONDARY -> $CURRENT_SECONDARY"
echo "  Total: $INITIAL_TOTAL -> $CURRENT_TOTAL"

# Check if primary insurance still exists (wasn't deleted or overwritten)
PRIMARY_PRESERVED="false"
if [ "$CURRENT_PRIMARY" -ge "$INITIAL_PRIMARY" ] && [ "$CURRENT_PRIMARY" -gt "0" ]; then
    PRIMARY_PRESERVED="true"
    echo "Primary insurance preserved: YES"
else
    echo "PRIMARY INSURANCE MISSING OR DELETED!"
fi

# Query for secondary insurance with expected policy number
echo ""
echo "=== Checking for new secondary insurance ==="
SECONDARY_DATA=$(openemr_query "SELECT id, type, provider, plan_name, policy_number, group_number, subscriber_relationship, date FROM insurance_data WHERE pid=$PATIENT_PID AND type='secondary' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Also check for any insurance with the expected policy number (in case type is wrong)
POLICY_MATCH=$(openemr_query "SELECT id, type, policy_number FROM insurance_data WHERE pid=$PATIENT_PID AND policy_number='$EXPECTED_POLICY'" 2>/dev/null)

# Parse secondary insurance data
SECONDARY_FOUND="false"
INS_ID=""
INS_TYPE=""
INS_PROVIDER=""
INS_PLAN=""
INS_POLICY=""
INS_GROUP=""
INS_SUBSCRIBER=""
INS_DATE=""

if [ -n "$SECONDARY_DATA" ]; then
    SECONDARY_FOUND="true"
    INS_ID=$(echo "$SECONDARY_DATA" | cut -f1)
    INS_TYPE=$(echo "$SECONDARY_DATA" | cut -f2)
    INS_PROVIDER=$(echo "$SECONDARY_DATA" | cut -f3)
    INS_PLAN=$(echo "$SECONDARY_DATA" | cut -f4)
    INS_POLICY=$(echo "$SECONDARY_DATA" | cut -f5)
    INS_GROUP=$(echo "$SECONDARY_DATA" | cut -f6)
    INS_SUBSCRIBER=$(echo "$SECONDARY_DATA" | cut -f7)
    INS_DATE=$(echo "$SECONDARY_DATA" | cut -f8)
    
    echo "Secondary insurance found:"
    echo "  ID: $INS_ID"
    echo "  Type: $INS_TYPE"
    echo "  Provider ID: $INS_PROVIDER"
    echo "  Plan: $INS_PLAN"
    echo "  Policy: $INS_POLICY"
    echo "  Group: $INS_GROUP"
    echo "  Subscriber: $INS_SUBSCRIBER"
    echo "  Date: $INS_DATE"
else
    echo "No secondary insurance found for patient"
fi

# Check if it was added during this task (secondary count increased)
NEWLY_ADDED="false"
if [ "$CURRENT_SECONDARY" -gt "$INITIAL_SECONDARY" ]; then
    NEWLY_ADDED="true"
    echo "Secondary insurance was newly added during task"
fi

# Validate fields
POLICY_CORRECT="false"
GROUP_CORRECT="false"
TYPE_CORRECT="false"
SUBSCRIBER_CORRECT="false"

if [ "$INS_POLICY" = "$EXPECTED_POLICY" ]; then
    POLICY_CORRECT="true"
    echo "Policy number matches expected value"
fi

if [ "$INS_GROUP" = "$EXPECTED_GROUP" ]; then
    GROUP_CORRECT="true"
    echo "Group number matches expected value"
fi

if [ "$INS_TYPE" = "secondary" ]; then
    TYPE_CORRECT="true"
    echo "Insurance type is correctly set to 'secondary'"
fi

# Subscriber relationship check (case-insensitive)
INS_SUBSCRIBER_LOWER=$(echo "$INS_SUBSCRIBER" | tr '[:upper:]' '[:lower:]')
if [ "$INS_SUBSCRIBER_LOWER" = "self" ]; then
    SUBSCRIBER_CORRECT="true"
    echo "Subscriber relationship is correctly set to 'self'"
fi

# Get insurance company name for the provider ID
INS_COMPANY_NAME=""
if [ -n "$INS_PROVIDER" ] && [ "$INS_PROVIDER" != "NULL" ] && [ "$INS_PROVIDER" != "0" ]; then
    INS_COMPANY_NAME=$(openemr_query "SELECT name FROM insurance_companies WHERE id=$INS_PROVIDER" 2>/dev/null)
    echo "Insurance company: $INS_COMPANY_NAME"
fi

# Check for policy match regardless of type (to catch if added as wrong type)
POLICY_EXISTS_ANY_TYPE="false"
if [ -n "$POLICY_MATCH" ]; then
    POLICY_EXISTS_ANY_TYPE="true"
    echo "Policy $EXPECTED_POLICY found (may be wrong type): $POLICY_MATCH"
fi

# Debug: Show all insurance for patient
echo ""
echo "=== All insurance records for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, type, policy_number, group_number, subscriber_relationship FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null
echo "=========================================================="

# Escape special characters for JSON
INS_PLAN_ESCAPED=$(echo "$INS_PLAN" | sed 's/"/\\"/g' | tr '\n' ' ')
INS_COMPANY_ESCAPED=$(echo "$INS_COMPANY_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/secondary_insurance_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_counts": {
        "primary": $INITIAL_PRIMARY,
        "secondary": $INITIAL_SECONDARY,
        "total": $INITIAL_TOTAL
    },
    "current_counts": {
        "primary": $CURRENT_PRIMARY,
        "secondary": $CURRENT_SECONDARY,
        "total": $CURRENT_TOTAL
    },
    "primary_preserved": $PRIMARY_PRESERVED,
    "secondary_found": $SECONDARY_FOUND,
    "newly_added": $NEWLY_ADDED,
    "insurance": {
        "id": "$INS_ID",
        "type": "$INS_TYPE",
        "provider_id": "$INS_PROVIDER",
        "company_name": "$INS_COMPANY_ESCAPED",
        "plan_name": "$INS_PLAN_ESCAPED",
        "policy_number": "$INS_POLICY",
        "group_number": "$INS_GROUP",
        "subscriber_relationship": "$INS_SUBSCRIBER",
        "effective_date": "$INS_DATE"
    },
    "validation": {
        "policy_correct": $POLICY_CORRECT,
        "group_correct": $GROUP_CORRECT,
        "type_correct": $TYPE_CORRECT,
        "subscriber_correct": $SUBSCRIBER_CORRECT,
        "policy_exists_any_type": $POLICY_EXISTS_ANY_TYPE
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/secondary_insurance_result.json 2>/dev/null || sudo rm -f /tmp/secondary_insurance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/secondary_insurance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/secondary_insurance_result.json
chmod 666 /tmp/secondary_insurance_result.json 2>/dev/null || sudo chmod 666 /tmp/secondary_insurance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/secondary_insurance_result.json"
cat /tmp/secondary_insurance_result.json
echo ""
echo "=== Export Complete ==="