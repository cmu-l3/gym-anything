#!/bin/bash
# Export script for Activate Clinical Decision Rule Task

echo "=== Exporting Activate Clinical Rule Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration
RULE_ID="rule_adult_wt_screen_fu"

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state
INITIAL_ACTIVE=$(cat /tmp/initial_rule_active 2>/dev/null || echo "0")

# Query current state of the rule
echo "Querying current rule state..."
CURRENT_STATE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT active, passive_alert, patient_reminder FROM clinical_rules WHERE id='$RULE_ID'" 2>/dev/null)

echo "Current rule state: $CURRENT_STATE"

# Parse the state values
CURRENT_ACTIVE=$(echo "$CURRENT_STATE" | cut -f1)
CURRENT_PASSIVE=$(echo "$CURRENT_STATE" | cut -f2)
CURRENT_REMINDER=$(echo "$CURRENT_STATE" | cut -f3)

# Handle empty/null values
CURRENT_ACTIVE=${CURRENT_ACTIVE:-0}
CURRENT_PASSIVE=${CURRENT_PASSIVE:-0}
CURRENT_REMINDER=${CURRENT_REMINDER:-0}

echo "Parsed values: active=$CURRENT_ACTIVE, passive=$CURRENT_PASSIVE, reminder=$CURRENT_REMINDER"

# Check if the rule was activated
RULE_ACTIVATED="false"
if [ "$CURRENT_ACTIVE" = "1" ]; then
    RULE_ACTIVATED="true"
    echo "SUCCESS: Rule has been activated!"
else
    echo "Rule is still inactive (active=$CURRENT_ACTIVE)"
fi

# Check if state changed from initial
STATE_CHANGED="false"
if [ "$CURRENT_ACTIVE" != "$INITIAL_ACTIVE" ]; then
    STATE_CHANGED="true"
    echo "State changed from $INITIAL_ACTIVE to $CURRENT_ACTIVE"
fi

# Get rule details for context
RULE_DETAILS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, active, passive_alert, patient_reminder, cqm_flag, amc_flag FROM clinical_rules WHERE id='$RULE_ID'" 2>/dev/null)
echo "Full rule details: $RULE_DETAILS"

# Check browser state
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Check if we're on the rules page (by checking window title or URL)
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
ON_RULES_PAGE="false"
if echo "$WINDOW_TITLE" | grep -qi "rules\|clinical\|administration"; then
    ON_RULES_PAGE="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/clinical_rule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rule_id": "$RULE_ID",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_active_state": $INITIAL_ACTIVE,
    "current_state": {
        "active": $CURRENT_ACTIVE,
        "passive_alert": $CURRENT_PASSIVE,
        "patient_reminder": $CURRENT_REMINDER
    },
    "rule_activated": $RULE_ACTIVATED,
    "state_changed": $STATE_CHANGED,
    "firefox_running": $FIREFOX_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "on_rules_page": $ON_RULES_PAGE,
    "screenshot_exists": $([ -f "/tmp/task_end_screenshot.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/clinical_rule_result.json 2>/dev/null || sudo rm -f /tmp/clinical_rule_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clinical_rule_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/clinical_rule_result.json
chmod 666 /tmp/clinical_rule_result.json 2>/dev/null || sudo chmod 666 /tmp/clinical_rule_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON:"
cat /tmp/clinical_rule_result.json
echo ""
echo "=== Export Complete ==="