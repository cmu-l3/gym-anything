#!/bin/bash
echo "=== Exporting upload_and_process_incident_report results ==="

source /workspace/scripts/task_utils.sh

# Ensure port forwarding is active for API calls
ensure_portforward

# Get Case ID
if [ -f /tmp/case_id.txt ]; then
    CASE_ID=$(cat /tmp/case_id.txt)
else
    echo "ERROR: Case ID not found."
    CASE_ID=""
fi

# 1. Fetch Case Details (for Incident Date)
echo "Fetching case details..."
CASE_DETAILS=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}" 2>/dev/null || echo "{}")

# 2. Fetch Case Notes (for Officer Name)
echo "Fetching case notes..."
CASE_NOTES=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}/notes" 2>/dev/null || echo "[]")

# 3. Fetch Case Documents (for Upload Verification)
# Note: ArkCase document API structure varies. We'll try listing children/contents.
echo "Fetching case documents..."
# Try generic container contents endpoint
CASE_DOCS=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    "${ARKCASE_URL}/api/v1/dms/folder/${CASE_ID}/list" 2>/dev/null || echo "[]")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "case_details": $CASE_DETAILS,
    "case_notes": $CASE_NOTES,
    "case_docs": $CASE_DOCS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"