#!/bin/bash
echo "=== Exporting create_study result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_study_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_study_count)

echo "Study count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

EXPECTED_NAME="Hypertension Management Trial"
EXPECTED_PROTOCOL="HMT-2024-001"

STUDY_FOUND="false"
STUDY_ID=""
STUDY_NAME=""
STUDY_PROTOCOL=""
STUDY_PI=""
STUDY_SUMMARY=""
STUDY_STATUS=""

# Try exact name match
STUDY_DATA=$(oc_query "SELECT study_id, name, unique_identifier, principal_investigator, summary, status_id FROM study WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) AND parent_study_id IS NULL ORDER BY study_id DESC LIMIT 1" 2>/dev/null)

# Try partial match if exact not found
if [ -z "$STUDY_DATA" ]; then
    echo "Exact match not found, trying partial match..."
    STUDY_DATA=$(oc_query "SELECT study_id, name, unique_identifier, principal_investigator, summary, status_id FROM study WHERE LOWER(name) LIKE '%hypertension%' AND parent_study_id IS NULL ORDER BY study_id DESC LIMIT 1" 2>/dev/null)
fi

# Try protocol ID match
if [ -z "$STUDY_DATA" ]; then
    echo "Name match not found, trying protocol ID match..."
    STUDY_DATA=$(oc_query "SELECT study_id, name, unique_identifier, principal_investigator, summary, status_id FROM study WHERE LOWER(unique_identifier) = LOWER('$EXPECTED_PROTOCOL') AND parent_study_id IS NULL ORDER BY study_id DESC LIMIT 1" 2>/dev/null)
fi

EXACT_MATCH="false"
# Check if this was from the exact match query
EXACT_DATA=$(oc_query "SELECT study_id FROM study WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) AND parent_study_id IS NULL ORDER BY study_id DESC LIMIT 1" 2>/dev/null)
if [ -n "$EXACT_DATA" ]; then
    EXACT_MATCH="true"
fi

if [ -n "$STUDY_DATA" ]; then
    STUDY_FOUND="true"
    STUDY_ID=$(echo "$STUDY_DATA" | cut -d'|' -f1)
    STUDY_NAME=$(echo "$STUDY_DATA" | cut -d'|' -f2)
    STUDY_PROTOCOL=$(echo "$STUDY_DATA" | cut -d'|' -f3)
    STUDY_PI=$(echo "$STUDY_DATA" | cut -d'|' -f4)
    STUDY_SUMMARY=$(echo "$STUDY_DATA" | cut -d'|' -f5)
    STUDY_STATUS=$(echo "$STUDY_DATA" | cut -d'|' -f6)

    echo "Found study ID: $STUDY_ID"
    echo "  Name: $STUDY_NAME"
    echo "  Protocol: $STUDY_PROTOCOL"
    echo "  PI: $STUDY_PI"
    echo "  Summary length: ${#STUDY_SUMMARY}"
else
    echo "No matching study found"
fi

STUDY_NAME_ESC=$(json_escape "$STUDY_NAME")
STUDY_PROTOCOL_ESC=$(json_escape "$STUDY_PROTOCOL")
STUDY_PI_ESC=$(json_escape "$STUDY_PI")
STUDY_SUMMARY_ESC=$(json_escape "$STUDY_SUMMARY")

# Query protocol_type for the found study
STUDY_PROTOCOL_TYPE=""
if [ -n "$STUDY_ID" ]; then
    STUDY_PROTOCOL_TYPE=$(oc_query "SELECT protocol_type FROM study WHERE study_id = $STUDY_ID" 2>/dev/null || echo "")
fi
echo "  Protocol type: $STUDY_PROTOCOL_TYPE"
STUDY_PROTOCOL_TYPE_ESC=$(json_escape "$STUDY_PROTOCOL_TYPE")

# Entity-specific audit: look for audit entries referencing study-related tables
AUDIT_STUDY_ENTRIES=$(get_audit_for_entity "study" 15)
AUDIT_ENTITY_TYPES=$(get_audit_entity_types 15)
echo "Audit: study-specific entries=$AUDIT_STUDY_ENTRIES, entity types=$AUDIT_ENTITY_TYPES"

TEMP_JSON=$(mktemp /tmp/create_study_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_study_count": ${INITIAL_COUNT:-0},
    "current_study_count": ${CURRENT_COUNT:-0},
    "study_found": $STUDY_FOUND,
    "exact_match": $EXACT_MATCH,
    "study": {
        "id": "${STUDY_ID:-}",
        "name": "$STUDY_NAME_ESC",
        "protocol_id": "$STUDY_PROTOCOL_ESC",
        "protocol_type": "$STUDY_PROTOCOL_TYPE_ESC",
        "principal_investigator": "$STUDY_PI_ESC",
        "summary": "$STUDY_SUMMARY_ESC",
        "summary_length": ${#STUDY_SUMMARY},
        "status_id": "${STUDY_STATUS:-}"
    },
    "audit_log_count": $(get_recent_audit_count 15),
    "audit_baseline_count": $(cat /tmp/audit_baseline_count 2>/dev/null || echo "0"),
    "audit_entity_count": ${AUDIT_STUDY_ENTRIES:-0},
    "audit_entity_types": "$(json_escape "$AUDIT_ENTITY_TYPES")",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_study_result.json"

echo ""
echo "=== Export complete ==="
