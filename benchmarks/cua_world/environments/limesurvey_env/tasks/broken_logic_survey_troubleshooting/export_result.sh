#!/bin/bash
echo "=== Exporting Troubleshooting Result ==="

source /workspace/scripts/task_utils.sh

# Define SID
SID=78901

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export the current state of the logic from the database
# We need to extract the relevance columns for the specific groups and questions

# 1. Get Group 101 relevance (Remote Work Tools)
# Expected fix: Should contain 'work_mode' and NOT 'work_style'
GROUP_RELEVANCE=$(limesurvey_query "SELECT relevance FROM lime_groups WHERE sid=$SID AND group_name='Remote Work Tools' LIMIT 1")

# 2. Get Q_Sales relevance
# Expected fix: Should contain "SALES" (closed quote)
Q_SALES_RELEVANCE=$(limesurvey_query "SELECT relevance FROM lime_questions WHERE sid=$SID AND title='Q_Sales' LIMIT 1")

# 3. Get Q_Shift relevance
# Expected fix: Should contain == "OPS" (double equals)
Q_SHIFT_RELEVANCE=$(limesurvey_query "SELECT relevance FROM lime_questions WHERE sid=$SID AND title='Q_Shift' LIMIT 1")

# Sanitize output for JSON (escape quotes)
GROUP_RELEVANCE_SAFE=$(echo "$GROUP_RELEVANCE" | sed 's/"/\\"/g' | tr -d '\n\r')
Q_SALES_RELEVANCE_SAFE=$(echo "$Q_SALES_RELEVANCE" | sed 's/"/\\"/g' | tr -d '\n\r')
Q_SHIFT_RELEVANCE_SAFE=$(echo "$Q_SHIFT_RELEVANCE" | sed 's/"/\\"/g' | tr -d '\n\r')

# Check if application (database) is still running
DB_RUNNING=$(docker ps | grep limesurvey-db > /dev/null && echo "true" || echo "false")

# Create JSON result
JSON_CONTENT=$(cat << EOF
{
    "survey_sid": $SID,
    "group_relevance": "$GROUP_RELEVANCE_SAFE",
    "q_sales_relevance": "$Q_SALES_RELEVANCE_SAFE",
    "q_shift_relevance": "$Q_SHIFT_RELEVANCE_SAFE",
    "db_running": $DB_RUNNING,
    "task_timestamp": "$(date -Iseconds)"
}
EOF
)

export_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "Exported Data:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="