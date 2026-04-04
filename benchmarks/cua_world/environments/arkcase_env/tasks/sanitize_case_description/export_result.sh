#!/bin/bash
set -e
echo "=== Exporting sanitize_case_description results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Read Configuration
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")
PII_PHONE=$(cat /tmp/sensitive_pii.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Verifying Case ID: $CASE_ID"
echo "Searching for removal of: $PII_PHONE"

# 3. Query ArkCase API for Current State
# We do this inside the container because we have easy access to localhost and credentials
if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "UNKNOWN" ]; then
    API_RESPONSE=$(arkcase_api GET "plugin/complaint/$CASE_ID" "")
    
    # Save raw response for debugging
    echo "$API_RESPONSE" > /tmp/case_final_state.json
    
    # Parse Description
    CURRENT_DESCRIPTION=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Description might be in 'details', 'description', or 'complaintDetails'
    print(data.get('details') or data.get('description') or data.get('complaintDetails') or '')
except:
    print('')
")
    
    # Get Modification Time (if available)
    LAST_MODIFIED=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Look for lastModified or similar timestamp
    print(data.get('lastModified', 0))
except:
    print('0')
")

else
    CURRENT_DESCRIPTION=""
    LAST_MODIFIED="0"
    echo "Warning: No valid Case ID to check."
fi

# 4. Analyze Results Locally
# Check if PII is present
if echo "$CURRENT_DESCRIPTION" | grep -qF "$PII_PHONE"; then
    PII_PRESENT="true"
else
    PII_PRESENT="false"
fi

# Check for Redaction Marker
if echo "$CURRENT_DESCRIPTION" | grep -qF "[REDACTED]"; then
    MARKER_PRESENT="true"
else
    MARKER_PRESENT="false"
fi

# Check Content Length (to ensure they didn't just delete everything)
DESC_LENGTH=${#CURRENT_DESCRIPTION}

# 5. Create JSON Result
# We write to a temp file then move to ensure atomicity
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "case_found": $([ -n "$CURRENT_DESCRIPTION" ] && echo "true" || echo "false"),
    "pii_target": "$PII_PHONE",
    "pii_present": $PII_PRESENT,
    "marker_present": $MARKER_PRESENT,
    "description_length": $DESC_LENGTH,
    "last_modified_ts": "$LAST_MODIFIED",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json