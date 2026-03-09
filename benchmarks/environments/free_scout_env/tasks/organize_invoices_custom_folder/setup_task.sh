#!/bin/bash
echo "=== Setting up organize_invoices_custom_folder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure 'Sales' mailbox exists
echo "Ensuring Sales mailbox exists..."
MAILBOX_ID=$(ensure_mailbox_exists "Sales" "sales@helpdesk.local")
echo "Sales Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/sales_mailbox_id.txt

# 2. Ensure 'Invoices' folder does NOT exist (clean state)
echo "Cleaning up old folders..."
fs_query "DELETE FROM folders WHERE mailbox_id = $MAILBOX_ID AND name = 'Invoices'"

# 3. Create the target conversation in the 'Sales' mailbox
SUBJECT="Invoice #2023-998 for December Consultation"
CUSTOMER_EMAIL="sarah.jenkins@example.com"
BODY="Hi team, I haven't received the invoice for the December consultation services yet. Can you please send it over? Thanks, Sarah."

# Get the ID of the standard 'Unassigned' folder (type 1) for this mailbox to ensure conversation starts there
UNASSIGNED_FOLDER_ID=$(fs_query "SELECT id FROM folders WHERE mailbox_id = $MAILBOX_ID AND type = 1 LIMIT 1")

# Check if conversation already exists
EXISTING_CONV_ID=$(fs_query "SELECT id FROM conversations WHERE mailbox_id = $MAILBOX_ID AND subject = '$SUBJECT' LIMIT 1")

if [ -z "$EXISTING_CONV_ID" ]; then
    echo "Creating new conversation..."
    CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "" "$BODY")
else
    echo "Resetting existing conversation..."
    CONV_ID=$EXISTING_CONV_ID
    # Force move back to Unassigned folder
    fs_query "UPDATE conversations SET folder_id = $UNASSIGNED_FOLDER_ID WHERE id = $CONV_ID"
fi
echo "Target Conversation ID: $CONV_ID"

# 4. Clear Cache to reflect DB changes in UI
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Launch Firefox
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="