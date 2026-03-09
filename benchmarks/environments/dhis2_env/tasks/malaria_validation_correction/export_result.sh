#!/bin/bash
# Export script for Malaria Validation Task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Fallbacks
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check for Validation Rule
echo "Checking for Validation Rule..."
RULE_INFO=$(dhis2_query "
    SELECT name, created, operator 
    FROM validationrule 
    WHERE name ILIKE '%Positive vs Tested%' 
    ORDER BY created DESC LIMIT 1;
")

RULE_EXISTS="false"
RULE_CREATED_AFTER="false"
RULE_OPERATOR=""

if [ -n "$RULE_INFO" ]; then
    RULE_EXISTS="true"
    # Extract operator (pipe separated in psql output usually)
    RULE_OPERATOR=$(echo "$RULE_INFO" | awk -F'|' '{print $3}' | tr -d ' ')
    
    # Check creation time against task start (roughly)
    # Using SQL to compare is easier
    CREATED_CHECK=$(dhis2_query "
        SELECT COUNT(*) FROM validationrule 
        WHERE name ILIKE '%Positive vs Tested%' 
        AND created > to_timestamp($TASK_START);
    " | tr -d ' ')
    
    if [ "$CREATED_CHECK" -gt 0 ]; then
        RULE_CREATED_AFTER="true"
    fi
fi

# 2. Check Data Values (The Correction)
echo "Checking Data Values..."

# Get UIDs again to be safe
TESTED_ID=$(dhis2_query "SELECT uid FROM dataelement WHERE name ILIKE 'Malaria RDT tested' LIMIT 1" | tr -d ' ')
POSITIVE_ID=$(dhis2_query "SELECT uid FROM dataelement WHERE name ILIKE 'Malaria RDT positive' LIMIT 1" | tr -d ' ')
ORG_ID=$(dhis2_query "SELECT uid FROM organisationunit WHERE name ILIKE 'Ngelehun CHC' LIMIT 1" | tr -d ' ')

# Query the values and timestamps
DATA_VALUES=$(dhis2_query "
    SELECT de.uid, dv.value, dv.lastupdated 
    FROM datavalue dv
    JOIN dataelement de ON dv.dataelementid = de.dataelementid
    JOIN period p ON dv.periodid = p.periodid
    JOIN organisationunit ou ON dv.sourceid = ou.organisationunitid
    WHERE p.iso = '202301' 
    AND ou.uid = '$ORG_ID'
    AND de.uid IN ('$TESTED_ID', '$POSITIVE_ID');
")

# Parse results
VAL_TESTED="0"
VAL_POSITIVE="0"
TIME_TESTED=""
TIME_POSITIVE=""

while read -r line; do
    UID=$(echo "$line" | awk -F'|' '{print $1}' | tr -d ' ')
    VAL=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ')
    TIME=$(echo "$line" | awk -F'|' '{print $3}' | tr -d ' ')
    
    if [ "$UID" == "$TESTED_ID" ]; then
        VAL_TESTED="$VAL"
        TIME_TESTED="$TIME"
    elif [ "$UID" == "$POSITIVE_ID" ]; then
        VAL_POSITIVE="$VAL"
        TIME_POSITIVE="$TIME"
    fi
done <<< "$DATA_VALUES"

# Check if Positive was updated after task start
# Convert DB timestamp to epoch for comparison
POSITIVE_UPDATED_RECENTLY="false"
if [ -n "$TIME_POSITIVE" ]; then
    TIME_EPOCH=$(date -d "$TIME_POSITIVE" +%s 2>/dev/null || echo "0")
    if [ "$TIME_EPOCH" -ge "$TASK_START" ]; then
        POSITIVE_UPDATED_RECENTLY="true"
    fi
fi

# 3. Create JSON Result
cat > /tmp/malaria_validation_correction_result.json << EOF
{
    "task_start_epoch": $TASK_START,
    "rule_exists": $RULE_EXISTS,
    "rule_created_after_start": $RULE_CREATED_AFTER,
    "rule_operator": "$RULE_OPERATOR",
    "value_tested": "$VAL_TESTED",
    "value_positive": "$VAL_POSITIVE",
    "positive_updated_recently": $POSITIVE_UPDATED_RECENTLY,
    "time_positive_last_updated": "$TIME_POSITIVE"
}
EOF

chmod 666 /tmp/malaria_validation_correction_result.json 2>/dev/null || true
echo "Result exported to /tmp/malaria_validation_correction_result.json"
cat /tmp/malaria_validation_correction_result.json