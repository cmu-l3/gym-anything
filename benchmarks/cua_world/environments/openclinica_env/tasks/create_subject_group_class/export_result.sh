#!/bin/bash
echo "=== Exporting create_subject_group_class result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")

# Query class information
CLASS_DATA=$(oc_query "SELECT study_group_class_id, name, group_class_type_id FROM study_group_class WHERE study_id = $DM_STUDY_ID AND name = 'Treatment Arm' ORDER BY study_group_class_id DESC LIMIT 1" 2>/dev/null || echo "")

CLASS_EXISTS="false"
CLASS_ID=""
CLASS_NAME=""
CLASS_TYPE_ID=""

if [ -n "$CLASS_DATA" ] && echo "$CLASS_DATA" | grep -q "|"; then
    CLASS_EXISTS="true"
    CLASS_ID=$(echo "$CLASS_DATA" | cut -d'|' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    CLASS_NAME=$(echo "$CLASS_DATA" | cut -d'|' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    CLASS_TYPE_ID=$(echo "$CLASS_DATA" | cut -d'|' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
fi

# Extract and format groups into JSON safely
if [ "$CLASS_EXISTS" = "true" ] && [ -n "$CLASS_ID" ]; then
    GROUP_DATA=$(oc_query "SELECT name, REPLACE(description, CHR(10), ' ') FROM study_group WHERE study_group_class_id = $CLASS_ID" 2>/dev/null || echo "")
    GROUPS_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
groups = []
for line in lines:
    if not line or '|' not in line: continue
    parts = line.split('|', 1)
    if len(parts) >= 2:
        groups.append({'name': parts[0].strip(), 'description': parts[1].strip()})
print(json.dumps(groups))
" <<< "$GROUP_DATA")
else
    GROUPS_JSON="[]"
fi

CURRENT_CLASS_COUNT=$(oc_query "SELECT COUNT(*) FROM study_group_class" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
CURRENT_GROUP_COUNT=$(oc_query "SELECT COUNT(*) FROM study_group" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

INITIAL_CLASS_COUNT=$(cat /tmp/initial_class_count 2>/dev/null || echo "0")
INITIAL_GROUP_COUNT=$(cat /tmp/initial_group_count 2>/dev/null || echo "0")

# Collect audit counts for anti-gaming checks
if type get_recent_audit_count >/dev/null 2>&1; then
    AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
else
    AUDIT_LOG_COUNT=100
fi
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "result_nonce": "$NONCE",
    "class_exists": $CLASS_EXISTS,
    "class_id": "$CLASS_ID",
    "class_name": "$CLASS_NAME",
    "class_type_id": "$CLASS_TYPE_ID",
    "groups": $GROUPS_JSON,
    "initial_class_count": $INITIAL_CLASS_COUNT,
    "initial_group_count": $INITIAL_GROUP_COUNT,
    "current_class_count": $CURRENT_CLASS_COUNT,
    "current_group_count": $CURRENT_GROUP_COUNT,
    "audit_log_count": $AUDIT_LOG_COUNT,
    "audit_baseline_count": $AUDIT_BASELINE_COUNT
}
EOF

# Move payload to a location safely accessible by verifier
rm -f /tmp/create_subject_group_class_result.json 2>/dev/null || sudo rm -f /tmp/create_subject_group_class_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_subject_group_class_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_subject_group_class_result.json
chmod 666 /tmp/create_subject_group_class_result.json 2>/dev/null || sudo chmod 666 /tmp/create_subject_group_class_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="