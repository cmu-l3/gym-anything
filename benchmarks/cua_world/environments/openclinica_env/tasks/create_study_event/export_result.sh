#!/bin/bash
echo "=== Exporting create_study_event result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_event_def_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_event_def_count)

echo "Event def count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

EXPECTED_NAME="Screening Visit"

# Get the expected study_id for the DM trial
EXPECTED_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "")
echo "Expected study_id: $EXPECTED_STUDY_ID"

EVENT_FOUND="false"
EVENT_ID=""
EVENT_NAME=""
EVENT_DESC=""
EVENT_TYPE=""
EVENT_REPEATING=""
EVENT_STATUS=""
EVENT_STUDY_ID=""

# Exact name match — filter by study_id for the DM trial
if [ -n "$EXPECTED_STUDY_ID" ]; then
    EVENT_DATA=$(oc_query "SELECT study_event_definition_id, name, description, type, repeating, status_id, study_id FROM study_event_definition WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) AND study_id = $EXPECTED_STUDY_ID ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
fi

# Fallback: exact name match without study filter
if [ -z "$EVENT_DATA" ]; then
    EVENT_DATA=$(oc_query "SELECT study_event_definition_id, name, description, type, repeating, status_id, study_id FROM study_event_definition WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
fi

# Partial match
if [ -z "$EVENT_DATA" ]; then
    echo "Exact match not found, trying partial..."
    EVENT_DATA=$(oc_query "SELECT study_event_definition_id, name, description, type, repeating, status_id, study_id FROM study_event_definition WHERE LOWER(name) LIKE '%screening%' ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
fi

EXACT_MATCH="false"
CORRECT_STUDY="false"
# Check if exact match in correct study
if [ -n "$EXPECTED_STUDY_ID" ]; then
    EXACT_DATA=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) AND study_id = $EXPECTED_STUDY_ID ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$EXACT_DATA" ]; then
        EXACT_MATCH="true"
        CORRECT_STUDY="true"
    else
        # Check exact match in any study
        EXACT_DATA=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) ORDER BY study_event_definition_id DESC LIMIT 1" 2>/dev/null)
        if [ -n "$EXACT_DATA" ]; then
            EXACT_MATCH="true"
        fi
    fi
fi

if [ -n "$EVENT_DATA" ]; then
    EVENT_FOUND="true"
    EVENT_ID=$(echo "$EVENT_DATA" | cut -d'|' -f1)
    EVENT_NAME=$(echo "$EVENT_DATA" | cut -d'|' -f2)
    EVENT_DESC=$(echo "$EVENT_DATA" | cut -d'|' -f3)
    EVENT_TYPE=$(echo "$EVENT_DATA" | cut -d'|' -f4)
    EVENT_REPEATING=$(echo "$EVENT_DATA" | cut -d'|' -f5)
    EVENT_STATUS=$(echo "$EVENT_DATA" | cut -d'|' -f6)
    EVENT_STUDY_ID=$(echo "$EVENT_DATA" | cut -d'|' -f7)

    echo "Found event: $EVENT_NAME (ID: $EVENT_ID, study_id: $EVENT_STUDY_ID)"
    echo "  Type: $EVENT_TYPE, Repeating: $EVENT_REPEATING"

    # Check if this event is in the correct study
    if [ "$EVENT_STUDY_ID" = "$EXPECTED_STUDY_ID" ]; then
        CORRECT_STUDY="true"
    fi
else
    echo "No matching event found"
fi

EVENT_NAME_ESC=$(json_escape "$EVENT_NAME")
EVENT_DESC_ESC=$(json_escape "$EVENT_DESC")
EVENT_TYPE_ESC=$(json_escape "$EVENT_TYPE")

# Entity-specific audit: look for study_event_definition entries
AUDIT_EVENT_ENTRIES=$(get_audit_for_entity "study_event_definition" 15)
AUDIT_ENTITY_TYPES=$(get_audit_entity_types 15)
echo "Audit: event-specific entries=$AUDIT_EVENT_ENTRIES, entity types=$AUDIT_ENTITY_TYPES"

TEMP_JSON=$(mktemp /tmp/create_event_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_event_def_count": ${INITIAL_COUNT:-0},
    "current_event_def_count": ${CURRENT_COUNT:-0},
    "event_found": $EVENT_FOUND,
    "exact_match": $EXACT_MATCH,
    "correct_study": $CORRECT_STUDY,
    "event": {
        "id": "${EVENT_ID:-}",
        "name": "$EVENT_NAME_ESC",
        "description": "$EVENT_DESC_ESC",
        "type": "$EVENT_TYPE_ESC",
        "repeating": "${EVENT_REPEATING:-}",
        "study_id": "${EVENT_STUDY_ID:-}",
        "status_id": "${EVENT_STATUS:-}"
    },
    "expected_study_id": "${EXPECTED_STUDY_ID:-}",
    "audit_log_count": $(get_recent_audit_count 15),
    "audit_baseline_count": $(cat /tmp/audit_baseline_count 2>/dev/null || echo "0"),
    "audit_entity_count": ${AUDIT_EVENT_ENTRIES:-0},
    "audit_entity_types": "$(json_escape "$AUDIT_ENTITY_TYPES")",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_study_event_result.json"

echo ""
echo "=== Export complete ==="
