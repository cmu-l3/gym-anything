#!/bin/bash
set -e
echo "=== Exporting Formalize Risk Acceptance results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Database for Risk Status
# We need: strategy_id, description, review_date, modified_time
# Note: In Eramba DB, 'risk_mitigation_strategy_id' holds the strategy (1=Accept usually)
# We fetch timestamps as UNIX_TIMESTAMP for easy comparison in python
SQL_QUERY="SELECT risk_mitigation_strategy_id, description, review, UNIX_TIMESTAMP(modified), id \
           FROM risks \
           WHERE title='Legacy ERP - Windows 2008' AND deleted=0 LIMIT 1;"

RISK_DATA=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$SQL_QUERY" 2>/dev/null)

# Parse the tab-separated result
# Default values if query fails
STRATEGY_ID="0"
DESCRIPTION=""
REVIEW_DATE=""
MODIFIED_TS="0"
RISK_ID="0"

if [ -n "$RISK_DATA" ]; then
    STRATEGY_ID=$(echo "$RISK_DATA" | awk -F'\t' '{print $1}')
    DESCRIPTION=$(echo "$RISK_DATA" | awk -F'\t' '{print $2}')
    REVIEW_DATE=$(echo "$RISK_DATA" | awk -F'\t' '{print $3}')
    MODIFIED_TS=$(echo "$RISK_DATA" | awk -F'\t' '{print $4}')
    RISK_ID=$(echo "$RISK_DATA" | awk -F'\t' '{print $5}')
fi

# 4. Query Database for Attachments
# Check if file is attached to this risk
ATTACHMENT_FOUND="false"
ATTACHMENT_FILENAME=""
ATTACHMENT_CREATED_TS="0"

if [ "$RISK_ID" != "0" ]; then
    # foreign_key links to risk.id, model is 'Risks'
    ATT_QUERY="SELECT filename, UNIX_TIMESTAMP(created) FROM attachments \
               WHERE model='Risks' AND foreign_key=${RISK_ID} AND filename='CEO_Risk_SignOff.pdf' \
               AND deleted=0 ORDER BY created DESC LIMIT 1;"
    
    ATT_DATA=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$ATT_QUERY" 2>/dev/null)
    
    if [ -n "$ATT_DATA" ]; then
        ATTACHMENT_FOUND="true"
        ATTACHMENT_FILENAME=$(echo "$ATT_DATA" | awk -F'\t' '{print $1}')
        ATTACHMENT_CREATED_TS=$(echo "$ATT_DATA" | awk -F'\t' '{print $2}')
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "risk_found": $(if [ "$RISK_ID" != "0" ]; then echo "true"; else echo "false"; fi),
    "strategy_id": $STRATEGY_ID,
    "description": $(echo "$DESCRIPTION" | jq -R .),
    "review_date": "$REVIEW_DATE",
    "risk_modified_ts": $MODIFIED_TS,
    "attachment_found": $ATTACHMENT_FOUND,
    "attachment_filename": "$ATTACHMENT_FILENAME",
    "attachment_created_ts": $ATTACHMENT_CREATED_TS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result with correct permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result data saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="