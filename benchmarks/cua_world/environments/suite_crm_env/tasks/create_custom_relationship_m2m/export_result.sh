#!/bin/bash
echo "=== Exporting create_custom_relationship_m2m results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Verify Relationship Definition
REL_INFO=$(suitecrm_db_query "SELECT relationship_name, relationship_type FROM relationships WHERE ((lhs_module='Opportunities' AND rhs_module='Bugs') OR (lhs_module='Bugs' AND rhs_module='Opportunities')) AND deleted=0 ORDER BY date_modified DESC LIMIT 1")
REL_NAME=$(echo "$REL_INFO" | awk -F'\t' '{print $1}')
REL_TYPE=$(echo "$REL_INFO" | awk -F'\t' '{print $2}')

# 2. Verify Physical Join Table Deployment
TABLE_INFO=$(suitecrm_db_query "SELECT TABLE_NAME, UNIX_TIMESTAMP(CREATE_TIME) FROM information_schema.tables WHERE table_schema='suitecrm' AND (table_name LIKE '%opportunities_bugs%' OR table_name LIKE '%bugs_opportunities%') AND table_name LIKE '%\_c' LIMIT 1")
JOIN_TABLE=$(echo "$TABLE_INFO" | awk -F'\t' '{print $1}')
TABLE_CREATE_TIME=$(echo "$TABLE_INFO" | awk -F'\t' '{print $2}')

# 3. Verify Record Linkage
OPP_ID="opp-meridian-1234"
BUG_ID="bug-mobile-5678"
RECORDS_LINKED="false"

if [ -n "$JOIN_TABLE" ]; then
    # We query the custom join table and grep for BOTH UUIDs in the output row to confirm linkage
    LINK_MATCH=$(suitecrm_db_query "SELECT * FROM $JOIN_TABLE WHERE deleted=0" | grep "$OPP_ID" | grep "$BUG_ID" || echo "")
    if [ -n "$LINK_MATCH" ]; then
        RECORDS_LINKED="true"
    fi
fi

# 4. Generate JSON Output
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "relationship_name": "$(json_escape "${REL_NAME:-}")",
  "relationship_type": "$(json_escape "${REL_TYPE:-}")",
  "join_table_name": "$(json_escape "${JOIN_TABLE:-}")",
  "join_table_create_time": ${TABLE_CREATE_TIME:-0},
  "records_linked": $RECORDS_LINKED
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== export complete ==="