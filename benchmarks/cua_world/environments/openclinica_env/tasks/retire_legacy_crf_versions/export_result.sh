#!/bin/bash
echo "=== Exporting retire_legacy_crf_versions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve CRF States
# 1 = Available, 5 = Removed

echo "Querying Database for Vital Signs statuses..."
VS_PARENT_STATUS=$(oc_query "SELECT status_id FROM crf WHERE name = 'Vital Signs' LIMIT 1")
VS_V1_STATUS=$(oc_query "SELECT status_id FROM crf_version WHERE name = 'v1.0' AND crf_id = (SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1) LIMIT 1")
VS_V2_STATUS=$(oc_query "SELECT status_id FROM crf_version WHERE name = 'v2.0' AND crf_id = (SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1) LIMIT 1")

echo "Querying Database for Physical Exam statuses..."
PE_PARENT_STATUS=$(oc_query "SELECT status_id FROM crf WHERE name = 'Physical Exam' LIMIT 1")
PE_V1_STATUS=$(oc_query "SELECT status_id FROM crf_version WHERE name = 'v1.0' AND crf_id = (SELECT crf_id FROM crf WHERE name = 'Physical Exam' LIMIT 1) LIMIT 1")
PE_V2_STATUS=$(oc_query "SELECT status_id FROM crf_version WHERE name = 'v2.0' AND crf_id = (SELECT crf_id FROM crf WHERE name = 'Physical Exam' LIMIT 1) LIMIT 1")

# Get Audit Delta
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
AUDIT_DELTA=$((AUDIT_LOG_COUNT - AUDIT_BASELINE_COUNT))

# Result Nonce
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "missing")

# Export to JSON
TEMP_JSON=$(mktemp /tmp/retire_crf_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "vs_parent_status": ${VS_PARENT_STATUS:-0},
    "vs_v1_status": ${VS_V1_STATUS:-0},
    "vs_v2_status": ${VS_V2_STATUS:-0},
    "pe_parent_status": ${PE_PARENT_STATUS:-0},
    "pe_v1_status": ${PE_V1_STATUS:-0},
    "pe_v2_status": ${PE_V2_STATUS:-0},
    "audit_delta": ${AUDIT_DELTA:-0},
    "result_nonce": "$NONCE"
}
EOF

# Move securely
rm -f /tmp/retire_legacy_crf_versions_result.json 2>/dev/null || sudo rm -f /tmp/retire_legacy_crf_versions_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/retire_legacy_crf_versions_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/retire_legacy_crf_versions_result.json
chmod 666 /tmp/retire_legacy_crf_versions_result.json 2>/dev/null || sudo chmod 666 /tmp/retire_legacy_crf_versions_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/retire_legacy_crf_versions_result.json"
cat /tmp/retire_legacy_crf_versions_result.json
echo "=== Export Complete ==="