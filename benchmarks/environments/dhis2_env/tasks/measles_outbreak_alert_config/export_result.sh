#!/bin/bash
# Export script for Measles Outbreak Alert Configuration task

echo "=== Exporting Measles Alert Configuration Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying DHIS2 Metadata objects..."

# 1. Check User Groups
echo "Checking User Groups..."
USER_GROUPS=$(dhis2_api "userGroups?filter=name:ilike:Emergency&fields=id,name,users[id,username]&paging=false")

# 2. Check Validation Rules
echo "Checking Validation Rules..."
# We check for rules with 'Measles' in the name
RULES=$(dhis2_api "validationRules?filter=name:ilike:Measles&fields=id,name,description,operator,leftSide[expression,description],rightSide[expression,description]&paging=false")

# 3. Check Validation Rule Groups
echo "Checking Validation Rule Groups..."
RULE_GROUPS=$(dhis2_api "validationRuleGroups?filter=name:ilike:Epidemic&fields=id,name,validationRules[id,name]&paging=false")

# 4. Check Validation Notifications
echo "Checking Validation Notification Templates..."
# We check all templates to find one that might be named correctly
NOTIFICATIONS=$(dhis2_api "validationNotificationTemplates?fields=id,name,validationRules[id,name],validationRuleGroups[id,name],recipientUserGroups[id,name],messageTemplate&paging=false")

# Combine into one JSON
cat > /tmp/measles_alert_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "user_groups_data": $USER_GROUPS,
    "validation_rules_data": $RULES,
    "validation_rule_groups_data": $RULE_GROUPS,
    "notifications_data": $NOTIFICATIONS,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/measles_alert_result.json 2>/dev/null || true
echo "Result exported to /tmp/measles_alert_result.json"

echo "=== Export Complete ==="