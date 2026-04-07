#!/bin/bash
echo "=== Exporting protocol_amendment_events result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(cat /tmp/dm_study_id 2>/dev/null)
if [ -z "$DM_STUDY_ID" ]; then
    DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
fi

echo "DM Trial study_id: $DM_STUDY_ID"

# ── Function to query event defs safely ────────────────────────────────────────
get_event_data() {
    local pattern="$1"
    local raw_data
    raw_data=$(oc_query "SELECT status_id, LOWER(type), repeating::text FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '$pattern' ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$raw_data" ]; then
        echo "$raw_data"
    else
        echo "0||"
    fi
}

# ── Retrieve DB State ──────────────────────────────────────────────────────────
FOLLOWUP_DATA=$(get_event_data "follow-up visit")
WEEK4_DATA=$(get_event_data "%week%4%safety%")
WEEK12_DATA=$(get_event_data "%week%12%efficacy%")
UNSCHED_DATA=$(get_event_data "%unscheduled%safety%")
END_TRT_DATA=$(get_event_data "%end%treatment%")
BASELINE_DATA=$(get_event_data "baseline assessment")

# ── Audit Log and Basics ───────────────────────────────────────────────────────
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")
CURRENT_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND status_id = 1" 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# ── Construct JSON ─────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/protocol_amendment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "result_nonce": "$NONCE",
    "audit_baseline": $AUDIT_BASELINE_COUNT,
    "audit_current": $AUDIT_LOG_COUNT,
    "initial_event_count": $INITIAL_EVENT_COUNT,
    "current_event_count": $CURRENT_EVENT_COUNT,
    "followup": {
        "status": $(echo "$FOLLOWUP_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$FOLLOWUP_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$FOLLOWUP_DATA" | cut -d'|' -f3)"
    },
    "week4": {
        "status": $(echo "$WEEK4_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$WEEK4_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$WEEK4_DATA" | cut -d'|' -f3)"
    },
    "week12": {
        "status": $(echo "$WEEK12_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$WEEK12_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$WEEK12_DATA" | cut -d'|' -f3)"
    },
    "unsched": {
        "status": $(echo "$UNSCHED_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$UNSCHED_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$UNSCHED_DATA" | cut -d'|' -f3)"
    },
    "end_trt": {
        "status": $(echo "$END_TRT_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$END_TRT_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$END_TRT_DATA" | cut -d'|' -f3)"
    },
    "baseline": {
        "status": $(echo "$BASELINE_DATA" | cut -d'|' -f1 | { read v; echo ${v:-0}; }),
        "type": "$(echo "$BASELINE_DATA" | cut -d'|' -f2)",
        "repeating": "$(echo "$BASELINE_DATA" | cut -d'|' -f3)"
    }
}
EOF

# Move securely to prevent permission errors
rm -f /tmp/protocol_amendment_result.json 2>/dev/null || sudo rm -f /tmp/protocol_amendment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/protocol_amendment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/protocol_amendment_result.json
chmod 666 /tmp/protocol_amendment_result.json 2>/dev/null || sudo chmod 666 /tmp/protocol_amendment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/protocol_amendment_result.json"
cat /tmp/protocol_amendment_result.json

echo "=== Export complete ==="