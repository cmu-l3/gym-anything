#!/bin/bash
echo "=== Exporting reassign_complaint_case result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/complaint_case_id.txt 2>/dev/null || echo "")

# Take final screenshot (CRITICAL for VLM)
take_screenshot /tmp/task_final.png

# ── 1. Fetch Final Case State via API ────────────────────────────────────────
echo "Fetching final case state for ID: $CASE_ID..."

CASE_DATA="{}"
if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "unknown" ]; then
    CASE_DATA=$(curl -sk -X GET \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}" 2>/dev/null || echo "{}")
fi

# Check if fetch was successful
if echo "$CASE_DATA" | grep -q "complaintTitle"; then
    echo "Case data retrieved successfully."
else
    echo "WARNING: Could not retrieve case data via API."
    CASE_DATA="{}"
fi

# ── 2. Create Result JSON ────────────────────────────────────────────────────
# We construct a clean JSON for the verifier to parse
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "case_data": $CASE_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="