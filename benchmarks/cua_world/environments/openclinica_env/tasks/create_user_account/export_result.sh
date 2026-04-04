#!/bin/bash
echo "=== Exporting create_user_account result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_user_count)

echo "User count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

EXPECTED_USERNAME="jsmith"

USER_FOUND="false"
USER_ID=""
USER_NAME=""
USER_FIRST=""
USER_LAST=""
USER_EMAIL=""
USER_STATUS=""
USER_ROLE=""
USER_AFFILIATION=""

# Try exact username match
USER_DATA=$(oc_query "SELECT user_id, user_name, first_name, last_name, email, status_id, institutional_affiliation FROM user_account WHERE LOWER(TRIM(user_name)) = LOWER(TRIM('$EXPECTED_USERNAME')) ORDER BY user_id DESC LIMIT 1" 2>/dev/null)

# Partial match
if [ -z "$USER_DATA" ]; then
    echo "Exact match not found, trying partial..."
    USER_DATA=$(oc_query "SELECT user_id, user_name, first_name, last_name, email, status_id, institutional_affiliation FROM user_account WHERE LOWER(user_name) LIKE '%jsmith%' OR (LOWER(first_name) = 'john' AND LOWER(last_name) = 'smith') ORDER BY user_id DESC LIMIT 1" 2>/dev/null)
fi

EXACT_MATCH="false"
# Check if exact match query succeeds
EXACT_DATA=$(oc_query "SELECT user_id FROM user_account WHERE LOWER(TRIM(user_name)) = LOWER(TRIM('$EXPECTED_USERNAME')) ORDER BY user_id DESC LIMIT 1" 2>/dev/null)
if [ -n "$EXACT_DATA" ]; then
    EXACT_MATCH="true"
fi

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | cut -d'|' -f1)
    USER_NAME=$(echo "$USER_DATA" | cut -d'|' -f2)
    USER_FIRST=$(echo "$USER_DATA" | cut -d'|' -f3)
    USER_LAST=$(echo "$USER_DATA" | cut -d'|' -f4)
    USER_EMAIL=$(echo "$USER_DATA" | cut -d'|' -f5)
    USER_STATUS=$(echo "$USER_DATA" | cut -d'|' -f6)
    USER_AFFILIATION=$(echo "$USER_DATA" | cut -d'|' -f7)

    echo "Found user: $USER_NAME ($USER_FIRST $USER_LAST)"
    echo "  Affiliation: $USER_AFFILIATION"

    # Check role assignment — include study_id to verify correct study assignment
    USER_ROLE_DATA=$(oc_query "SELECT sur.role_name, sur.study_id FROM study_user_role sur JOIN user_account ua ON sur.user_name = ua.user_name WHERE LOWER(ua.user_name) = LOWER('$USER_NAME') ORDER BY sur.study_user_role_id DESC LIMIT 1" 2>/dev/null || echo "")
    USER_ROLE=$(echo "$USER_ROLE_DATA" | cut -d'|' -f1)
    USER_ROLE_STUDY_ID=$(echo "$USER_ROLE_DATA" | cut -d'|' -f2)
    echo "  Role: $USER_ROLE (study_id: $USER_ROLE_STUDY_ID)"
else
    echo "No matching user found"
fi

# Debug
echo ""
echo "=== DEBUG: Recent users ==="
oc_query "SELECT user_id, user_name, first_name, last_name FROM user_account ORDER BY user_id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

USER_NAME_ESC=$(json_escape "$USER_NAME")
USER_FIRST_ESC=$(json_escape "$USER_FIRST")
USER_LAST_ESC=$(json_escape "$USER_LAST")
USER_EMAIL_ESC=$(json_escape "$USER_EMAIL")
USER_ROLE_ESC=$(json_escape "$USER_ROLE")
USER_AFFILIATION_ESC=$(json_escape "$USER_AFFILIATION")

# Get expected study_id for the DM trial to verify role was assigned to correct study
EXPECTED_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "")
ROLE_IN_CORRECT_STUDY="false"
if [ -n "$USER_ROLE_STUDY_ID" ] && [ "$USER_ROLE_STUDY_ID" = "$EXPECTED_STUDY_ID" ]; then
    ROLE_IN_CORRECT_STUDY="true"
fi
echo "Role study check: role_study=$USER_ROLE_STUDY_ID, expected=$EXPECTED_STUDY_ID, correct=$ROLE_IN_CORRECT_STUDY"

# Entity-specific audit: look for user_account entries
AUDIT_USER_ENTRIES=$(get_audit_for_entity "user_account" 15)
AUDIT_ENTITY_TYPES=$(get_audit_entity_types 15)
echo "Audit: user-specific entries=$AUDIT_USER_ENTRIES, entity types=$AUDIT_ENTITY_TYPES"

TEMP_JSON=$(mktemp /tmp/create_user_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_user_count": ${INITIAL_COUNT:-0},
    "current_user_count": ${CURRENT_COUNT:-0},
    "user_found": $USER_FOUND,
    "exact_match": $EXACT_MATCH,
    "user": {
        "id": "${USER_ID:-}",
        "username": "$USER_NAME_ESC",
        "first_name": "$USER_FIRST_ESC",
        "last_name": "$USER_LAST_ESC",
        "email": "$USER_EMAIL_ESC",
        "role": "$USER_ROLE_ESC",
        "role_study_id": "${USER_ROLE_STUDY_ID:-}",
        "role_in_correct_study": $ROLE_IN_CORRECT_STUDY,
        "affiliation": "$USER_AFFILIATION_ESC",
        "status_id": "${USER_STATUS:-}"
    },
    "audit_log_count": $(get_recent_audit_count 15),
    "audit_baseline_count": $(cat /tmp/audit_baseline_count 2>/dev/null || echo "0"),
    "audit_entity_count": ${AUDIT_USER_ENTRIES:-0},
    "audit_entity_types": "$(json_escape "$AUDIT_ENTITY_TYPES")",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_user_account_result.json"

echo ""
echo "=== Export complete ==="
