#!/bin/bash
set -e

echo "=== Exporting block_inbound_spam_numbers result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Verification
# We need to check:
# - Filter Group Existence
# - Number in Filter Group
# - DID Configuration

echo "Querying Vicidial database..."

# Helper to run SQL in docker
run_sql() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "$1" 2>/dev/null
}

# Check Filter Group
GROUP_DATA=$(run_sql "SELECT filter_phone_group_id, group_name FROM vicidial_filter_phone_groups WHERE filter_phone_group_id='SPAMBLOCK'")
GROUP_EXISTS="false"
GROUP_NAME=""
if [ -n "$GROUP_DATA" ]; then
    GROUP_EXISTS="true"
    GROUP_NAME=$(echo "$GROUP_DATA" | awk '{print $2}') # Simple awk, assumes no spaces in ID. Name might have spaces.
    # Better parsing for name with spaces:
    GROUP_NAME=$(echo "$GROUP_DATA" | cut -f2)
fi

# Check Number
SPAM_NUM="2025550188"
NUMBER_DATA=$(run_sql "SELECT phone_number FROM vicidial_filter_phone_numbers WHERE filter_phone_group_id='SPAMBLOCK' AND phone_number='$SPAM_NUM'")
NUMBER_ADDED="false"
if [ -n "$NUMBER_DATA" ]; then
    NUMBER_ADDED="true"
fi

# Check DID Config
DID_PATTERN="8885550100"
DID_DATA=$(run_sql "SELECT filter_inbound_number, filter_phone_group_id, filter_action FROM vicidial_inbound_dids WHERE did_pattern='$DID_PATTERN'")
DID_FILTER_STATUS=""
DID_FILTER_GROUP=""
DID_ACTION=""

if [ -n "$DID_DATA" ]; then
    DID_FILTER_STATUS=$(echo "$DID_DATA" | cut -f1)
    DID_FILTER_GROUP=$(echo "$DID_DATA" | cut -f2)
    DID_ACTION=$(echo "$DID_DATA" | cut -f3)
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "group_exists": $GROUP_EXISTS,
    "group_name": "$GROUP_NAME",
    "number_added": $NUMBER_ADDED,
    "did_filter_status": "$DID_FILTER_STATUS",
    "did_filter_group": "$DID_FILTER_GROUP",
    "did_action": "$DID_ACTION",
    "task_timestamp": $(date +%s)
}
EOF

# 4. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. content:"
cat /tmp/task_result.json