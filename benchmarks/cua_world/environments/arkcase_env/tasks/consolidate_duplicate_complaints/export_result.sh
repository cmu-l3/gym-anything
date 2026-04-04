#!/bin/bash
# Export script for Consolidate Duplicate Complaints task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Load Task Data
MASTER_ID=$(cat /tmp/master_case_id.txt 2>/dev/null || echo "")
DUPLICATE_ID=$(cat /tmp/duplicate_case_id.txt 2>/dev/null || echo "")
EXPECTED_CONTENT=$(cat /tmp/expected_note_content.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Verifying Master: $MASTER_ID"
echo "Verifying Duplicate: $DUPLICATE_ID"

# 1. Check Master Case Notes (Data Preservation)
echo "Checking Master Case Notes..."
# Endpoint structure may vary, usually /service/note/COMPLAINT/{id}
NOTES_RESPONSE=$(arkcase_api GET "service/note/COMPLAINT/$MASTER_ID" 2>/dev/null)
# Check if any note contains the unique description
NOTE_FOUND=$(echo "$NOTES_RESPONSE" | grep -F "$EXPECTED_CONTENT" > /dev/null && echo "true" || echo "false")
echo "Note content found: $NOTE_FOUND"

# 2. Check Associations (Link Established)
echo "Checking Associations..."
# Endpoint: /service/objectassociation/COMPLAINT/{id}/COMPLAINT
ASSOC_RESPONSE=$(arkcase_api GET "service/objectassociation/COMPLAINT/$MASTER_ID/COMPLAINT" 2>/dev/null)
# Check if Duplicate ID is in the association list
LINK_FOUND=$(echo "$ASSOC_RESPONSE" | grep -F "$DUPLICATE_ID" > /dev/null && echo "true" || echo "false")
# Bi-directional check
if [ "$LINK_FOUND" = "false" ]; then
    ASSOC_RESPONSE_B=$(arkcase_api GET "service/objectassociation/COMPLAINT/$DUPLICATE_ID/COMPLAINT" 2>/dev/null)
    LINK_FOUND=$(echo "$ASSOC_RESPONSE_B" | grep -F "$MASTER_ID" > /dev/null && echo "true" || echo "false")
fi
echo "Link found: $LINK_FOUND"

# 3. Check Duplicate Case Status (Duplicate Closed)
echo "Checking Duplicate Status..."
DUP_INFO=$(arkcase_api GET "plugin/complaint/$DUPLICATE_ID" 2>/dev/null)
DUP_STATUS=$(echo "$DUP_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'Unknown'))" 2>/dev/null)
echo "Duplicate Status: $DUP_STATUS"

# 4. Check Master Case Status (Master Active)
echo "Checking Master Status..."
MASTER_INFO=$(arkcase_api GET "plugin/complaint/$MASTER_ID" 2>/dev/null)
MASTER_STATUS=$(echo "$MASTER_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'Unknown'))" 2>/dev/null)
echo "Master Status: $MASTER_STATUS"

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "master_id": "$MASTER_ID",
    "duplicate_id": "$DUPLICATE_ID",
    "note_preserved": $NOTE_FOUND,
    "link_established": $LINK_FOUND,
    "duplicate_status": "$DUP_STATUS",
    "master_status": "$MASTER_STATUS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json