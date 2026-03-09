#!/bin/bash
# Export script for Email Newsletter Campaign task

echo "=== Exporting Email Newsletter Campaign Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# Retrieve initial counts
INITIAL_TEMPLATE_COUNT=$(cat /tmp/initial_template_count 2>/dev/null || echo "0")
INITIAL_SUBSCRIBER_COUNT=$(cat /tmp/initial_subscriber_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. CHECK CONFIGURATION
echo "Checking configuration..."
ALLOW_GUEST=$(magento_query "SELECT value FROM core_config_data WHERE path='newsletter/subscription/allow_guest_subscribe'" 2>/dev/null | tail -1)
NEED_CONFIRM=$(magento_query "SELECT value FROM core_config_data WHERE path='newsletter/subscription/confirm'" 2>/dev/null | tail -1)
echo "Config: allow_guest=$ALLOW_GUEST confirm=$NEED_CONFIRM"

# 2. CHECK NEWSLETTER TEMPLATE
echo "Checking newsletter template..."
TEMPLATE_DATA=$(magento_query "SELECT template_id, template_code, template_subject, template_sender_name, template_sender_email, template_text, added_at FROM newsletter_template WHERE LOWER(TRIM(template_code))='holiday collection 2024' ORDER BY template_id DESC LIMIT 1" 2>/dev/null | tail -1)

TEMPLATE_FOUND="false"
TEMPLATE_ID=""
TEMPLATE_SUBJECT=""
TEMPLATE_SENDER_NAME=""
TEMPLATE_SENDER_EMAIL=""
TEMPLATE_CONTENT=""
TEMPLATE_ADDED_AT=""

if [ -n "$TEMPLATE_DATA" ]; then
    TEMPLATE_FOUND="true"
    TEMPLATE_ID=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $1}')
    TEMPLATE_SUBJECT=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $3}')
    TEMPLATE_SENDER_NAME=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $4}')
    TEMPLATE_SENDER_EMAIL=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $5}')
    TEMPLATE_CONTENT=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $6}')
    TEMPLATE_ADDED_AT=$(echo "$TEMPLATE_DATA" | awk -F'\t' '{print $7}')
fi
echo "Template found: $TEMPLATE_FOUND"

# Check HTML content
HAS_H1="false"
HAS_P="false"
HAS_LIST="false"
if [ "$TEMPLATE_FOUND" = "true" ]; then
    echo "$TEMPLATE_CONTENT" | grep -qi "<h1" && HAS_H1="true"
    echo "$TEMPLATE_CONTENT" | grep -qi "<p" && HAS_P="true"
    echo "$TEMPLATE_CONTENT" | grep -qi "<ul\|<ol" && HAS_LIST="true"
fi

# 3. CHECK SUBSCRIBERS
echo "Checking subscribers..."
TARGET_EMAILS="'alice.johnson@example.com','bob.smith@example.com','carol.williams@example.com','david.brown@example.com','emma.davis@example.com'"

# Get count of valid subscribers among target list
# Status 1 = Subscribed
SUBSCRIBER_COUNT=$(magento_query "SELECT COUNT(*) FROM newsletter_subscriber WHERE subscriber_status=1 AND subscriber_email IN ($TARGET_EMAILS)" 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "Target subscribers found: $SUBSCRIBER_COUNT"

# Get details for feedback
SUBSCRIBER_DETAILS=$(magento_query "SELECT subscriber_email, subscriber_status FROM newsletter_subscriber WHERE subscriber_email IN ($TARGET_EMAILS)" 2>/dev/null)

# Escape JSON strings
TEMPLATE_SUBJECT_ESC=$(echo "$TEMPLATE_SUBJECT" | sed 's/"/\\"/g')
TEMPLATE_SENDER_NAME_ESC=$(echo "$TEMPLATE_SENDER_NAME" | sed 's/"/\\"/g')
TEMPLATE_SENDER_EMAIL_ESC=$(echo "$TEMPLATE_SENDER_EMAIL" | sed 's/"/\\"/g')
# Be careful with content, might be large/multiline
TEMPLATE_CONTENT_ESC="" # Not exporting full content to JSON to avoid parsing issues, just flags

TEMP_JSON=$(mktemp /tmp/newsletter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_template_count": ${INITIAL_TEMPLATE_COUNT:-0},
    "initial_subscriber_count": ${INITIAL_SUBSCRIBER_COUNT:-0},
    "config_allow_guest": "${ALLOW_GUEST:-0}",
    "config_need_confirm": "${NEED_CONFIRM:-1}",
    "template_found": $TEMPLATE_FOUND,
    "template_subject": "$TEMPLATE_SUBJECT_ESC",
    "template_sender_name": "$TEMPLATE_SENDER_NAME_ESC",
    "template_sender_email": "$TEMPLATE_SENDER_EMAIL_ESC",
    "template_has_h1": $HAS_H1,
    "template_has_p": $HAS_P,
    "template_has_list": $HAS_LIST,
    "template_added_at": "$TEMPLATE_ADDED_AT",
    "target_subscriber_count": ${SUBSCRIBER_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/newsletter_result.json

echo ""
cat /tmp/newsletter_result.json
echo ""
echo "=== Export Complete ==="