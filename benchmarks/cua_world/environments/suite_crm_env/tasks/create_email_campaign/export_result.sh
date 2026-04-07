#!/bin/bash
echo "=== Exporting Create Email Campaign task results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Gather Baseline Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_campaign_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_count "campaigns" "deleted=0")
TARGET_LIST_ID=$(cat /tmp/target_list_id.txt 2>/dev/null | tr -d '[:space:]')

# 3. Query the Database for the Expected Campaign
CAMP_DATA=$(suitecrm_db_query "SELECT id, name, campaign_type, budget, start_date, end_date, status, description, UNIX_TIMESTAMP(date_entered) FROM campaigns WHERE name='Q3 Industrial Equipment Launch' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

CAMP_FOUND="false"
C_ID=""
C_NAME=""
C_TYPE=""
C_BUDGET=""
C_START=""
C_END=""
C_STATUS=""
C_DESC=""
C_TS="0"
LINK_COUNT="0"

if [ -n "$CAMP_DATA" ]; then
    CAMP_FOUND="true"
    C_ID=$(echo "$CAMP_DATA" | awk -F'\t' '{print $1}')
    C_NAME=$(echo "$CAMP_DATA" | awk -F'\t' '{print $2}')
    C_TYPE=$(echo "$CAMP_DATA" | awk -F'\t' '{print $3}')
    C_BUDGET=$(echo "$CAMP_DATA" | awk -F'\t' '{print $4}')
    C_START=$(echo "$CAMP_DATA" | awk -F'\t' '{print $5}')
    C_END=$(echo "$CAMP_DATA" | awk -F'\t' '{print $6}')
    C_STATUS=$(echo "$CAMP_DATA" | awk -F'\t' '{print $7}')
    C_DESC=$(echo "$CAMP_DATA" | awk -F'\t' '{print $8}')
    C_TS=$(echo "$CAMP_DATA" | awk -F'\t' '{print $9}')
    
    # Check if the target list was successfully associated
    if [ -n "$C_ID" ] && [ -n "$TARGET_LIST_ID" ]; then
        LINK_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_list_campaigns WHERE campaign_id='${C_ID}' AND prospect_list_id='${TARGET_LIST_ID}' AND deleted=0" | tr -d '[:space:]')
    fi
fi

# 4. Generate JSON Output using Python to ensure safe escaping
python3 -c "
import json
import os

data = {
    'task_start_time': int('${TASK_START}'),
    'initial_count': int('${INITIAL_COUNT}'),
    'current_count': int('${CURRENT_COUNT}'),
    'target_list_id': '${TARGET_LIST_ID}',
    'campaign_found': '${CAMP_FOUND}' == 'true',
    'campaign_data': {
        'id': '${C_ID}',
        'name': '''${C_NAME}''',
        'type': '''${C_TYPE}''',
        'budget': '''${C_BUDGET}''',
        'start_date': '''${C_START}''',
        'end_date': '''${C_END}''',
        'status': '''${C_STATUS}''',
        'description': '''${C_DESC}''',
        'created_timestamp': int('${C_TS}')
    },
    'target_list_links': int('${LINK_COUNT}')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 5. Make result accessible
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="