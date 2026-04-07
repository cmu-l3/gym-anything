#!/bin/bash
echo "=== Exporting create_dynamic_email_template results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for visual verification
take_screenshot /tmp/task_final.png

# Query the database for the newly created template
# Use jq to safely serialize potentially multiline HTML body content
echo "Querying database for template..."
T_ID=$(vtiger_db_query "SELECT templateid FROM vtiger_emailtemplates WHERE templatename='Standard Post-Demo Follow-up' AND deleted=0 LIMIT 1" | tr -d '[:space:]')

if [ -n "$T_ID" ]; then
    TEMPLATE_FOUND="true"
    T_SUBJECT=$(vtiger_db_query "SELECT subject FROM vtiger_emailtemplates WHERE templateid=$T_ID LIMIT 1")
    T_MODULE=$(vtiger_db_query "SELECT module FROM vtiger_emailtemplates WHERE templateid=$T_ID LIMIT 1")
    
    # Save body to a temp file to handle tabs/newlines safely
    vtiger_db_query "SELECT body FROM vtiger_emailtemplates WHERE templateid=$T_ID LIMIT 1" > /tmp/template_body_raw.txt
    T_BODY=$(cat /tmp/template_body_raw.txt)
else
    TEMPLATE_FOUND="false"
    T_ID=""
    T_SUBJECT=""
    T_MODULE=""
    T_BODY=""
fi

# Use jq to safely construct the JSON output
jq -n \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    --arg found "$TEMPLATE_FOUND" \
    --arg id "$T_ID" \
    --arg subject "$T_SUBJECT" \
    --arg module "$T_MODULE" \
    --arg body "$T_BODY" \
    '{
        task_start: $task_start | tonumber,
        task_end: $task_end | tonumber,
        template_found: ($found == "true"),
        template_id: $id,
        subject: $subject,
        module: $module,
        body: $body
    }' > /tmp/create_email_template_result.json

chmod 666 /tmp/create_email_template_result.json 2>/dev/null || sudo chmod 666 /tmp/create_email_template_result.json 2>/dev/null || true

echo "Result saved to /tmp/create_email_template_result.json"
cat /tmp/create_email_template_result.json
echo "=== create_dynamic_email_template export complete ==="