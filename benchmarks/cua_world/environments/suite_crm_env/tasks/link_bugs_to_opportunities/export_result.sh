#!/bin/bash
echo "=== Exporting link_bugs_to_opportunities results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Check the `relationships` table for the Opportunity-Bug relationship
REL_QUERY="SELECT relationship_name, join_table, relationship_type FROM relationships WHERE ((lhs_module='Opportunities' AND rhs_module='Bugs') OR (lhs_module='Bugs' AND rhs_module='Opportunities')) AND deleted=0 LIMIT 1"
REL_DATA=$(suitecrm_db_query "$REL_QUERY")

REL_EXISTS="false"
JOIN_TABLE=""
REL_TYPE=""
REL_NAME=""

if [ -n "$REL_DATA" ]; then
    REL_EXISTS="true"
    REL_NAME=$(echo "$REL_DATA" | awk -F'\t' '{print $1}')
    JOIN_TABLE=$(echo "$REL_DATA" | awk -F'\t' '{print $2}')
    REL_TYPE=$(echo "$REL_DATA" | awk -F'\t' '{print $3}')
fi

# 3. Check if physical custom table exists in database
TABLE_EXISTS="false"
if [ -n "$JOIN_TABLE" ]; then
    CHECK_TABLE=$(suitecrm_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='suitecrm' AND table_name='$JOIN_TABLE'")
    if [ "$CHECK_TABLE" -gt 0 ]; then
        TABLE_EXISTS="true"
    fi
fi

# 4. Check if the specific Opportunity and Bug are linked
OPP_ID=$(suitecrm_db_query "SELECT id FROM opportunities WHERE name='GlobalMedia - 1000 Licenses' AND deleted=0 LIMIT 1")
BUG_ID=$(suitecrm_db_query "SELECT id FROM bugs WHERE name='Login page timeout error' AND deleted=0 LIMIT 1")

RECORDS_LINKED="false"
if [ "$TABLE_EXISTS" == "true" ] && [ -n "$OPP_ID" ] && [ -n "$BUG_ID" ]; then
    # Since column names are generated dynamically (e.g. opportunities_bugs_1opportunities_ida),
    # we scan the join table to see if any row contains BOTH IDs.
    LINK_ROWS=$(suitecrm_db_query "SELECT * FROM \`$JOIN_TABLE\` WHERE deleted=0")
    
    # Read rows and look for our target IDs
    while IFS= read -r row; do
        if echo "$row" | grep -q "$OPP_ID" && echo "$row" | grep -q "$BUG_ID"; then
            RECORDS_LINKED="true"
            break
        fi
    done <<< "$LINK_ROWS"
fi

# 5. Get metrics for anti-gaming checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REL_COUNT=$(cat /tmp/initial_rel_count.txt 2>/dev/null || echo "0")
CURRENT_REL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM relationships WHERE deleted=0")

# 6. Create export JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "relationship_metadata_exists": $REL_EXISTS,
  "relationship_name": "$(json_escape "${REL_NAME:-}")",
  "relationship_type": "$(json_escape "${REL_TYPE:-}")",
  "junction_table_name": "$(json_escape "${JOIN_TABLE:-}")",
  "junction_table_exists": $TABLE_EXISTS,
  "records_linked": $RECORDS_LINKED,
  "opportunity_id": "$(json_escape "${OPP_ID:-}")",
  "bug_id": "$(json_escape "${BUG_ID:-}")",
  "initial_relationship_count": $INITIAL_REL_COUNT,
  "current_relationship_count": $CURRENT_REL_COUNT
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="