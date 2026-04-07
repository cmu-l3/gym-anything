#!/bin/bash
echo "=== Exporting create_security_group_assignment results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot for evidence
take_screenshot /tmp/task_final_state.png

# Fetch task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Default export variables
SG_FOUND="false"
SG_ID=""
SG_DESC=""
SG_DATE=0
USER_LINK_COUNT=0
ACC1_LINK_COUNT=0
ACC2_LINK_COUNT=0

# Query 1: Find the Security Group
SG_DATA=$(suitecrm_db_query "SELECT id, description, UNIX_TIMESTAMP(date_entered) FROM securitygroups WHERE name='APAC Sales Region' AND deleted=0 LIMIT 1")

if [ -n "$SG_DATA" ]; then
    SG_FOUND="true"
    SG_ID=$(echo "$SG_DATA" | awk -F'\t' '{print $1}')
    SG_DESC=$(echo "$SG_DATA" | awk -F'\t' '{print $2}')
    SG_DATE=$(echo "$SG_DATA" | awk -F'\t' '{print $3}')
    
    # Check User Relationship (Akiko Lin)
    USER_LINK_COUNT=$(suitecrm_db_query "SELECT count(*) FROM securitygroups_users su JOIN users u ON su.user_id = u.id WHERE su.securitygroup_id = '${SG_ID}' AND u.last_name = 'Lin' AND su.deleted=0 AND u.deleted=0")
    
    # Check Target Account Relationship (Tokyo Electronics KK)
    ACC1_LINK_COUNT=$(suitecrm_db_query "SELECT count(*) FROM securitygroups_records sr JOIN accounts a ON sr.record_id = a.id WHERE sr.securitygroup_id = '${SG_ID}' AND a.name = 'Tokyo Electronics KK' AND sr.deleted=0 AND a.deleted=0")
    
    # Check Distractor Account Relationship (Tokyo Distribution Partners)
    ACC2_LINK_COUNT=$(suitecrm_db_query "SELECT count(*) FROM securitygroups_records sr JOIN accounts a ON sr.record_id = a.id WHERE sr.securitygroup_id = '${SG_ID}' AND a.name = 'Tokyo Distribution Partners' AND sr.deleted=0 AND a.deleted=0")
fi

# Construct Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START},
  "sg_found": ${SG_FOUND},
  "sg_id": "$(json_escape "${SG_ID:-}")",
  "sg_desc": "$(json_escape "${SG_DESC:-}")",
  "sg_date": ${SG_DATE:-0},
  "user_link_count": ${USER_LINK_COUNT:-0},
  "acc1_link_count": ${ACC1_LINK_COUNT:-0},
  "acc2_link_count": ${ACC2_LINK_COUNT:-0}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== create_security_group_assignment export complete ==="