#!/bin/bash
echo "=== Exporting archive_external_email results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# 1. Check local file creation
FILE_CREATED="false"
FILE_MTIME=0
if [ -f "/home/ga/Documents/Q4_Requirements.txt" ]; then
    FILE_CREATED="true"
    FILE_MTIME=$(stat -c %Y "/home/ga/Documents/Q4_Requirements.txt" 2>/dev/null || echo "0")
fi

# 2. Query Database for Account
ACCOUNT_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Global Tech Industries' AND deleted=0 LIMIT 1")

# 3. Query Database for Email
EMAIL_ID=$(suitecrm_db_query "SELECT id FROM emails WHERE name='URGENT: Q4 Procurement Requirements' AND deleted=0 LIMIT 1")

BODY_MATCH="false"
EMAIL_PARENT_TYPE=""
EMAIL_PARENT_ID=""

if [ -n "$EMAIL_ID" ]; then
    # Check if the email text contains the required snippet
    MATCH_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM emails_text WHERE email_id='${EMAIL_ID}' AND description LIKE '%hardware refresh%'")
    if [ "$MATCH_COUNT" -gt 0 ]; then
        BODY_MATCH="true"
    fi
    
    # Get native relationship fields directly on the email record
    EMAIL_PARENT_TYPE=$(suitecrm_db_query "SELECT parent_type FROM emails WHERE id='${EMAIL_ID}' LIMIT 1")
    EMAIL_PARENT_ID=$(suitecrm_db_query "SELECT parent_id FROM emails WHERE id='${EMAIL_ID}' LIMIT 1")
fi

# Check cross-table relationship just in case (SuiteCRM sometimes uses emails_beans for relating)
EB_REL="false"
if [ -n "$EMAIL_ID" ] && [ -n "$ACCOUNT_ID" ]; then
    EB_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM emails_beans WHERE email_id='${EMAIL_ID}' AND bean_id='${ACCOUNT_ID}' AND deleted=0")
    if [ "$EB_COUNT" -gt 0 ]; then
        EB_REL="true"
    fi
fi

# 4. Query Database for Notes (Attachments)
ATTACH_ID=$(suitecrm_db_query "SELECT id FROM notes WHERE filename='Q4_Requirements.txt' AND deleted=0 LIMIT 1")
ATTACH_PARENT_TYPE=""
ATTACH_PARENT_ID=""

if [ -n "$ATTACH_ID" ]; then
    ATTACH_PARENT_TYPE=$(suitecrm_db_query "SELECT parent_type FROM notes WHERE id='${ATTACH_ID}' LIMIT 1")
    ATTACH_PARENT_ID=$(suitecrm_db_query "SELECT parent_id FROM notes WHERE id='${ATTACH_ID}' LIMIT 1")
fi

# 5. Build Result JSON safely
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "local_file_created": $FILE_CREATED,
  "local_file_mtime": $FILE_MTIME,
  "account_id": "$(json_escape "${ACCOUNT_ID:-}")",
  "email_id": "$(json_escape "${EMAIL_ID:-}")",
  "body_match": $BODY_MATCH,
  "email_parent_type": "$(json_escape "${EMAIL_PARENT_TYPE:-}")",
  "email_parent_id": "$(json_escape "${EMAIL_PARENT_ID:-}")",
  "emails_beans_rel": $EB_REL,
  "attach_id": "$(json_escape "${ATTACH_ID:-}")",
  "attach_parent_type": "$(json_escape "${ATTACH_PARENT_TYPE:-}")",
  "attach_parent_id": "$(json_escape "${ATTACH_PARENT_ID:-}")"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat "/tmp/task_result.json"
echo "=== archive_external_email export complete ==="