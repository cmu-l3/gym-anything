#!/bin/bash
# Export script for Link Preferred Pharmacy task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Get stored IDs from setup
PATIENT_ID=$(cat /tmp/target_patient_id 2>/dev/null || echo "")
PHARMACY_ID=$(cat /tmp/target_pharmacy_id 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Checking link for Patient $PATIENT_ID and Pharmacy $PHARMACY_ID..."

# Check if link exists in demographicPharmacy table
# We select creationDate to verify it was made during the task
LINK_DATA=$(oscar_query "SELECT demographic_no, pharmacyid, creationDate, archived FROM demographicPharmacy WHERE demographic_no='$PATIENT_ID' AND pharmacyid='$PHARMACY_ID' LIMIT 1")

LINK_EXISTS="false"
LINK_ARCHIVED="false"
CREATION_DATE=""

if [ -n "$LINK_DATA" ]; then
    LINK_EXISTS="true"
    # Parse results (tab separated)
    # Col 1: demographic_no, Col 2: pharmacyid, Col 3: creationDate, Col 4: archived
    CREATION_DATE=$(echo "$LINK_DATA" | cut -f3)
    IS_ARCHIVED=$(echo "$LINK_DATA" | cut -f4)
    
    if [ "$IS_ARCHIVED" == "1" ]; then
        LINK_ARCHIVED="true"
    fi
    echo "Link found! Created: $CREATION_DATE, Archived: $LINK_ARCHIVED"
else
    echo "No link found in database."
fi

# Get total pharmacy links for this patient (just in case they linked the wrong one)
TOTAL_LINKS=$(oscar_query "SELECT COUNT(*) FROM demographicPharmacy WHERE demographic_no='$PATIENT_ID' AND archived=0" || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "target_patient_id": "$PATIENT_ID",
    "target_pharmacy_id": "$PHARMACY_ID",
    "link_exists": $LINK_EXISTS,
    "link_archived": $LINK_ARCHIVED,
    "creation_date": "$CREATION_DATE",
    "total_active_links": $TOTAL_LINKS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="