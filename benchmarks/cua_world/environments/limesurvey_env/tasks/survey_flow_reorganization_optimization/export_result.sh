#!/bin/bash
echo "=== Exporting Survey Flow Reorganization Result ==="

source /workspace/scripts/task_utils.sh

# Get Survey ID
SURVEY_ID=$(cat /tmp/task_survey_id 2>/dev/null)
if [ -z "$SURVEY_ID" ]; then
    # Fallback search if file missing
    SURVEY_ID=$(get_survey_id "Consumer Shopping Habits 2025")
fi

echo "Checking Survey ID: $SURVEY_ID"

# 1. Get Group Orders
# We need to map Group Name to Group Order
# Join with lime_groups_l10ns isn't always reliable for name if language differs, 
# but usually group_name is in lime_groups too.
echo "Querying group structure..."

# Fetch Group Info: GID, Name, Order
GROUP_DATA=$(limesurvey_query "SELECT gid, group_name, group_order FROM lime_groups WHERE sid=${SURVEY_ID} ORDER BY group_order ASC")

# Parse into variables
ORDER_CONSENT=999
ORDER_SHOPPING=999
ORDER_DEMO=999

while IFS=$'\t' read -r gid name order; do
    if [[ "$name" == *"Consent"* ]]; then
        ORDER_CONSENT=$order
    elif [[ "$name" == *"Shopping"* ]]; then
        ORDER_SHOPPING=$order
    elif [[ "$name" == *"Demographics"* ]]; then
        ORDER_DEMO=$order
    fi
done <<< "$GROUP_DATA"

echo "Group Orders Found: Consent=$ORDER_CONSENT, Shopping=$ORDER_SHOPPING, Demo=$ORDER_DEMO"

# 2. Get Question Mandatory Status
# CONSENT1 (should be Y)
MANDATORY_CONSENT=$(limesurvey_query "SELECT mandatory FROM lime_questions WHERE sid=${SURVEY_ID} AND title='CONSENT1'")
# DEMO_INC (should be N)
MANDATORY_INCOME=$(limesurvey_query "SELECT mandatory FROM lime_questions WHERE sid=${SURVEY_ID} AND title='DEMO_INC'")

echo "Question Attributes: Consent=$MANDATORY_CONSENT, Income=$MANDATORY_INCOME"

# 3. Application State Check
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
cat > /tmp/json_temp.json << EOF
{
    "survey_id": "$SURVEY_ID",
    "group_orders": {
        "consent": $ORDER_CONSENT,
        "shopping": $ORDER_SHOPPING,
        "demographics": $ORDER_DEMO
    },
    "questions": {
        "consent_mandatory": "$MANDATORY_CONSENT",
        "income_mandatory": "$MANDATORY_INCOME"
    },
    "app_running": $APP_RUNNING,
    "timestamp": "$(date +%s)"
}
EOF

export_json_result "$(cat /tmp/json_temp.json)" "/tmp/task_result.json"
rm /tmp/json_temp.json

echo "Result exported to /tmp/task_result.json"