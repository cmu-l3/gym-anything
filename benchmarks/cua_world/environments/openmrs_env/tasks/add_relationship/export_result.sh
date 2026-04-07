#!/bin/bash
echo "=== Exporting add_relationship result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Load internal state
if [ -f /tmp/task_internal_state.json ]; then
    PA_ID=$(grep -o '"person_a_id": "[^"]*"' /tmp/task_internal_state.json | cut -d'"' -f4)
    PB_ID=$(grep -o '"person_b_id": "[^"]*"' /tmp/task_internal_state.json | cut -d'"' -f4)
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
else
    echo "ERROR: Internal state not found"
    PA_ID=""
    PB_ID=""
    START_TIME="0"
fi

# 3. Check database for relationship
# We look for A->B or B->A where type is Sibling (or contains Sibling in description)
# Note: In standard OpenMRS CIEL, Sibling is often a specific UUID, but we check strings for robustness
# or we join with relationship_type.

echo "Checking database for relationship..."

# Query for the specific relationship
# Returns: uuid, a_is_to_b, date_created timestamp
REL_DATA=$(omrs_db_query "
    SELECT r.uuid, rt.a_is_to_b, rt.b_is_to_a, UNIX_TIMESTAMP(r.date_created)
    FROM relationship r
    JOIN relationship_type rt ON r.relationship = rt.relationship_type_id
    WHERE r.voided = 0
    AND (
        (r.person_a = $PA_ID AND r.person_b = $PB_ID)
        OR 
        (r.person_a = $PB_ID AND r.person_b = $PA_ID)
    )
    ORDER BY r.date_created DESC LIMIT 1
" 2>/dev/null)

REL_FOUND="false"
REL_TYPE=""
REL_TIMESTAMP="0"

if [ -n "$REL_DATA" ]; then
    REL_FOUND="true"
    # Parse result (tab separated)
    REL_UUID=$(echo "$REL_DATA" | awk '{print $1}')
    TYPE_A=$(echo "$REL_DATA" | awk '{print $2}')
    TYPE_B=$(echo "$REL_DATA" | awk '{print $3}')
    REL_TIMESTAMP=$(echo "$REL_DATA" | awk '{print $4}')
    
    # Combine types for checking
    REL_TYPE="$TYPE_A / $TYPE_B"
fi

# 4. Check global count increase
INITIAL_COUNT=$(cat /tmp/initial_rel_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM relationship WHERE voided=0" 2>/dev/null || echo "0")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "relationship_found": $REL_FOUND,
    "relationship_type": "$REL_TYPE",
    "creation_timestamp": ${REL_TIMESTAMP:-0},
    "task_start_time": ${START_TIME:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "final_count": ${FINAL_COUNT:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json