#!/bin/bash
echo "=== Exporting add_study_subject result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_subject_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_subject_count)

echo "Subject count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

EXPECTED_LABEL="SS-001"

SUBJECT_FOUND="false"
SUBJECT_ID=""
SUBJECT_LABEL=""
SUBJECT_GENDER=""
SUBJECT_DOB=""
SUBJECT_STATUS=""

# Try exact label match
SUBJECT_DATA=$(oc_query "SELECT ss.study_subject_id, ss.label, ss.enrollment_date, ss.status_id, sb.gender, sb.date_of_birth FROM study_subject ss LEFT JOIN subject sb ON ss.subject_id = sb.subject_id WHERE LOWER(TRIM(ss.label)) = LOWER(TRIM('$EXPECTED_LABEL')) ORDER BY ss.study_subject_id DESC LIMIT 1" 2>/dev/null)

# Partial match
if [ -z "$SUBJECT_DATA" ]; then
    echo "Exact match not found, trying partial..."
    SUBJECT_DATA=$(oc_query "SELECT ss.study_subject_id, ss.label, ss.enrollment_date, ss.status_id, sb.gender, sb.date_of_birth FROM study_subject ss LEFT JOIN subject sb ON ss.subject_id = sb.subject_id WHERE LOWER(ss.label) LIKE '%ss-001%' OR LOWER(ss.label) LIKE '%ss001%' ORDER BY ss.study_subject_id DESC LIMIT 1" 2>/dev/null)
fi

EXACT_MATCH="false"
# Check if exact match query succeeds
EXACT_DATA=$(oc_query "SELECT ss.study_subject_id FROM study_subject ss WHERE LOWER(TRIM(ss.label)) = LOWER(TRIM('$EXPECTED_LABEL')) ORDER BY ss.study_subject_id DESC LIMIT 1" 2>/dev/null)
if [ -n "$EXACT_DATA" ]; then
    EXACT_MATCH="true"
fi

if [ -n "$SUBJECT_DATA" ]; then
    SUBJECT_FOUND="true"
    SUBJECT_ID=$(echo "$SUBJECT_DATA" | cut -d'|' -f1)
    SUBJECT_LABEL=$(echo "$SUBJECT_DATA" | cut -d'|' -f2)
    SUBJECT_ENROLLMENT=$(echo "$SUBJECT_DATA" | cut -d'|' -f3)
    SUBJECT_STATUS=$(echo "$SUBJECT_DATA" | cut -d'|' -f4)
    SUBJECT_GENDER=$(echo "$SUBJECT_DATA" | cut -d'|' -f5)
    SUBJECT_DOB=$(echo "$SUBJECT_DATA" | cut -d'|' -f6)

    echo "Found subject: $SUBJECT_LABEL (ID: $SUBJECT_ID)"
    echo "  Gender: $SUBJECT_GENDER, DOB: $SUBJECT_DOB"
else
    echo "No matching subject found"
fi

SUBJECT_LABEL_ESC=$(json_escape "$SUBJECT_LABEL")
SUBJECT_ENROLLMENT_ESC=$(json_escape "${SUBJECT_ENROLLMENT:-}")

# Entity-specific audit: look for study_subject entries
AUDIT_SUBJECT_ENTRIES=$(get_audit_for_entity "study_subject" 15)
AUDIT_ENTITY_TYPES=$(get_audit_entity_types 15)
echo "Audit: subject-specific entries=$AUDIT_SUBJECT_ENTRIES, entity types=$AUDIT_ENTITY_TYPES"

TEMP_JSON=$(mktemp /tmp/add_subject_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_subject_count": ${INITIAL_COUNT:-0},
    "current_subject_count": ${CURRENT_COUNT:-0},
    "subject_found": $SUBJECT_FOUND,
    "exact_match": $EXACT_MATCH,
    "subject": {
        "id": "${SUBJECT_ID:-}",
        "label": "$SUBJECT_LABEL_ESC",
        "gender": "${SUBJECT_GENDER:-}",
        "date_of_birth": "${SUBJECT_DOB:-}",
        "enrollment_date": "$SUBJECT_ENROLLMENT_ESC",
        "status_id": "${SUBJECT_STATUS:-}"
    },
    "audit_log_count": $(get_recent_audit_count 15),
    "audit_baseline_count": $(cat /tmp/audit_baseline_count 2>/dev/null || echo "0"),
    "audit_entity_count": ${AUDIT_SUBJECT_ENTRIES:-0},
    "audit_entity_types": "$(json_escape "$AUDIT_ENTITY_TYPES")",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/add_study_subject_result.json"

echo ""
echo "=== Export complete ==="
