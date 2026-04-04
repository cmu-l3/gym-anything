#!/bin/bash
# Export verification data for configure_system_announcement task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_system_announcement results ==="

RESULT_FILE="/tmp/configure_system_announcement_result.json"

# 1. Get current markup formatter via Groovy Script Console
echo "Checking markup formatter..."
FORMATTER_CLASS=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode "script=println Jenkins.instance.markupFormatter.class.name" \
  "$JENKINS_URL/scriptText" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
echo "Markup formatter class: $FORMATTER_CLASS"

# Determine formatter type
FORMATTER_TYPE="unknown"
if echo "$FORMATTER_CLASS" | grep -qi "RawHtmlMarkupFormatter\|HtmlMarkupFormatter"; then
    FORMATTER_TYPE="safe_html"
elif echo "$FORMATTER_CLASS" | grep -qi "EscapedMarkupFormatter"; then
    FORMATTER_TYPE="plain_text"
fi
echo "Formatter type: $FORMATTER_TYPE"

# 2. Get system message content
echo "Checking system message..."
# Retrieve JSON and extract description field safely
SYSTEM_MESSAGE=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/api/json" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msg = data.get('description', '') or ''
    # Output raw message for bash variable
    print(msg)
except:
    print('')
" 2>/dev/null || echo "")

SYSTEM_MESSAGE_LENGTH=${#SYSTEM_MESSAGE}
echo "System message length: $SYSTEM_MESSAGE_LENGTH"

# 3. Check for specific content in system message
HAS_MAINTENANCE_HEADING="false"
HAS_DATE_JAN25="false"
HAS_TIME_WINDOW="false"
HAS_BUILDS_SUSPENDED="false"
HAS_PIPELINES_PAUSED="false"
HAS_PLAN_ACCORDINGLY="false"
HAS_CONTACT_EMAIL="false"
HAS_HTML_TAGS="false"

# Case-insensitive checks
if echo "$SYSTEM_MESSAGE" | grep -qi "Scheduled Maintenance Notice"; then
    HAS_MAINTENANCE_HEADING="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "January 25.*2025"; then
    HAS_DATE_JAN25="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "02:00.*06:00.*UTC"; then
    HAS_TIME_WINDOW="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "builds will be suspended\|running builds.*suspended"; then
    HAS_BUILDS_SUSPENDED="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "pipeline.*paused\|pipelines.*paused"; then
    HAS_PIPELINES_PAUSED="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "plan your deployments accordingly\|plan.*accordingly"; then
    HAS_PLAN_ACCORDINGLY="true"
fi

if echo "$SYSTEM_MESSAGE" | grep -qi "devops-team@company.com"; then
    HAS_CONTACT_EMAIL="true"
fi

# Basic check for HTML tags to ensure they didn't just paste plain text
if echo "$SYSTEM_MESSAGE" | grep -qi "<div\|<h3\|<p>\|<ul>\|<li>\|<strong>\|<em>"; then
    HAS_HTML_TAGS="true"
fi

# 4. Get initial state for comparison
INITIAL_FORMATTER=$(cat /tmp/initial_markup_formatter.txt 2>/dev/null || echo "unknown")
INITIAL_MSG_LENGTH=$(wc -c < /tmp/initial_system_message.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Take screenshot of current dashboard
take_screenshot /tmp/task_final.png

# 6. Build JSON result
# Using python for safe JSON construction to handle special chars in system message
python3 -c "
import json
import os
import time

result = {
    'task_id': 'configure_system_announcement',
    'timestamp': int(time.time()),
    'task_start_time': $TASK_START_TIME,
    'markup_formatter': {
        'class_name': '$FORMATTER_CLASS',
        'type': '$FORMATTER_TYPE',
        'is_safe_html': True if '$FORMATTER_TYPE' == 'safe_html' else False
    },
    'system_message': {
        'length': $SYSTEM_MESSAGE_LENGTH,
        'is_non_empty': True if $SYSTEM_MESSAGE_LENGTH > 10 else False,
        'has_html_tags': True if '$HAS_HTML_TAGS' == 'true' else False,
        'content_checks': {
            'has_maintenance_heading': True if '$HAS_MAINTENANCE_HEADING' == 'true' else False,
            'has_date_jan25': True if '$HAS_DATE_JAN25' == 'true' else False,
            'has_time_window': True if '$HAS_TIME_WINDOW' == 'true' else False,
            'has_builds_suspended': True if '$HAS_BUILDS_SUSPENDED' == 'true' else False,
            'has_pipelines_paused': True if '$HAS_PIPELINES_PAUSED' == 'true' else False,
            'has_plan_accordingly': True if '$HAS_PLAN_ACCORDINGLY' == 'true' else False,
            'has_contact_email': True if '$HAS_CONTACT_EMAIL' == 'true' else False
        }
    },
    'initial_state': {
        'formatter': '$INITIAL_FORMATTER',
        'message_length': int('$INITIAL_MSG_LENGTH'.strip() or 0)
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo ""
echo "=== Export complete ==="