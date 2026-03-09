#!/bin/bash
echo "=== Exporting create_crf result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/initial_crf_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_crf_count)

echo "CRF count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

EXPECTED_NAME="Vital Signs"

CRF_FOUND="false"
CRF_ID=""
CRF_NAME=""
CRF_DESC=""
CRF_STATUS=""
CRF_VERSION=""
CRF_ITEM_COUNT="0"

# Exact name match
CRF_DATA=$(oc_query "SELECT crf_id, name, description, status_id FROM crf WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) ORDER BY crf_id DESC LIMIT 1" 2>/dev/null)

# Partial match
if [ -z "$CRF_DATA" ]; then
    echo "Exact match not found, trying partial..."
    CRF_DATA=$(oc_query "SELECT crf_id, name, description, status_id FROM crf WHERE LOWER(name) LIKE '%vital%' ORDER BY crf_id DESC LIMIT 1" 2>/dev/null)
fi

EXACT_MATCH="false"
# Check if exact match query succeeds
EXACT_DATA=$(oc_query "SELECT crf_id FROM crf WHERE LOWER(TRIM(name)) = LOWER(TRIM('$EXPECTED_NAME')) ORDER BY crf_id DESC LIMIT 1" 2>/dev/null)
if [ -n "$EXACT_DATA" ]; then
    EXACT_MATCH="true"
fi

if [ -n "$CRF_DATA" ]; then
    CRF_FOUND="true"
    CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
    CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
    CRF_DESC=$(echo "$CRF_DATA" | cut -d'|' -f3)
    CRF_STATUS=$(echo "$CRF_DATA" | cut -d'|' -f4)

    echo "Found CRF: $CRF_NAME (ID: $CRF_ID)"

    # Get CRF version info
    CRF_VERSION=$(oc_query "SELECT name FROM crf_version WHERE crf_id = $CRF_ID ORDER BY crf_version_id DESC LIMIT 1" 2>/dev/null || echo "")
    echo "  Version: $CRF_VERSION"

    # Get CRF item count
    CRF_VERSION_ID=$(oc_query "SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID ORDER BY crf_version_id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$CRF_VERSION_ID" ]; then
        CRF_ITEM_COUNT=$(oc_query "SELECT COUNT(*) FROM item_form_metadata WHERE crf_version_id = $CRF_VERSION_ID" 2>/dev/null || echo "0")
    fi
    echo "  Item count: $CRF_ITEM_COUNT"
else
    echo "No matching CRF found"
fi

CRF_NAME_ESC=$(json_escape "$CRF_NAME")
CRF_DESC_ESC=$(json_escape "$CRF_DESC")
CRF_VERSION_ESC=$(json_escape "$CRF_VERSION")

# Entity-specific audit: look for crf entries
AUDIT_CRF_ENTRIES=$(get_audit_for_entity "crf" 15)
AUDIT_ENTITY_TYPES=$(get_audit_entity_types 15)
echo "Audit: crf-specific entries=$AUDIT_CRF_ENTRIES, entity types=$AUDIT_ENTITY_TYPES"

TEMP_JSON=$(mktemp /tmp/create_crf_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_crf_count": ${INITIAL_COUNT:-0},
    "current_crf_count": ${CURRENT_COUNT:-0},
    "crf_found": $CRF_FOUND,
    "exact_match": $EXACT_MATCH,
    "crf": {
        "id": "${CRF_ID:-}",
        "name": "$CRF_NAME_ESC",
        "description": "$CRF_DESC_ESC",
        "version": "$CRF_VERSION_ESC",
        "item_count": ${CRF_ITEM_COUNT:-0},
        "status_id": "${CRF_STATUS:-}"
    },
    "audit_log_count": $(get_recent_audit_count 15),
    "audit_baseline_count": $(cat /tmp/audit_baseline_count 2>/dev/null || echo "0"),
    "audit_entity_count": ${AUDIT_CRF_ENTRIES:-0},
    "audit_entity_types": "$(json_escape "$AUDIT_ENTITY_TYPES")",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_crf_result.json"

echo ""
echo "=== Export complete ==="
