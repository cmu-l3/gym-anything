#!/bin/bash
# post_task: Export results for grant_foia_fee_waiver

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Case Data via API
CASE_GUID=$(cat /tmp/task_case_guid.txt 2>/dev/null || echo "")

API_DATA="{}"
if [ -n "$CASE_GUID" ]; then
    echo "Fetching data for case GUID: $CASE_GUID"
    # Fetch full complaint details
    API_DATA=$(arkcase_api GET "plugin/complaint/${CASE_GUID}" "" 2>/dev/null || echo "{}")
else
    echo "WARNING: No Case GUID found. Agent may have failed to load context or setup failed."
fi

# 3. Create Result JSON
# We include the raw API data so the python verifier can parse the specific fields safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time 2>/dev/null || echo "0"),
    "task_end": $(date +%s),
    "case_guid": "$CASE_GUID",
    "api_response": $API_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"