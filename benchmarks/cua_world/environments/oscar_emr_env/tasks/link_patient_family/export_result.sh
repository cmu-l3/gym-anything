#!/bin/bash
# Export script for Link Patient Family task
# Checks the database for the established relationship

echo "=== Exporting Link Patient Family Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve stored IDs and table name
MOM_ID=$(cat /tmp/mom_id.txt 2>/dev/null)
SON_ID=$(cat /tmp/son_id.txt 2>/dev/null)
LINK_TABLE=$(cat /tmp/link_table_name.txt 2>/dev/null || echo "link_demographic")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Checking link between Son ($SON_ID) and Mom ($MOM_ID) in table $LINK_TABLE..."

# Check Direction 1: Son -> Mom
LINK_DATA_1=$(oscar_query "SELECT relation, date FROM $LINK_TABLE WHERE demographic_no='$SON_ID' AND demographic_no_related='$MOM_ID'")

# Check Direction 2: Mom -> Son (Some implementations link both ways or use inverse)
LINK_DATA_2=$(oscar_query "SELECT relation, date FROM $LINK_TABLE WHERE demographic_no='$MOM_ID' AND demographic_no_related='$SON_ID'")

LINK_FOUND="false"
RELATION_TYPE=""
LINK_DATE=""

if [ -n "$LINK_DATA_1" ]; then
    LINK_FOUND="true"
    RELATION_TYPE=$(echo "$LINK_DATA_1" | awk '{print $1}')
    LINK_DATE=$(echo "$LINK_DATA_1" | awk '{print $2}') # Assuming date is 2nd col
    echo "Found Link (Son->Mom): $RELATION_TYPE"
elif [ -n "$LINK_DATA_2" ]; then
    LINK_FOUND="true"
    RELATION_TYPE=$(echo "$LINK_DATA_2" | awk '{print $1}')
    LINK_DATE=$(echo "$LINK_DATA_2" | awk '{print $2}')
    echo "Found Link (Mom->Son): $RELATION_TYPE"
fi

# Check for modification time (Anti-gaming)
# If the link table has a date field, we check it. 
# Otherwise, we check the lastUpdateDate on the child's demographic record.
RECORD_UPDATED="false"
LAST_UPDATE=$(oscar_query "SELECT lastUpdateDate FROM demographic WHERE demographic_no='$SON_ID'")
# Convert SQL datetime to seconds (approximation for check)
# Simple check: is lastUpdateDate >= today?
TODAY=$(date +%Y-%m-%d)
if [[ "$LAST_UPDATE" == *"$TODAY"* ]]; then
    RECORD_UPDATED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "link_found": $LINK_FOUND,
    "relation_type": "$RELATION_TYPE",
    "mom_id": "$MOM_ID",
    "son_id": "$SON_ID",
    "record_updated_today": $RECORD_UPDATED,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="