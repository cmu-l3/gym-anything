#!/bin/bash
set -e
echo "=== Setting up recover_and_purge_trash task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for FreeScout to be ready
wait_for_freescout_ready() {
    for i in {1..30}; do
        if curl -s http://localhost:8080/login > /dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_for_freescout_ready || echo "WARNING: FreeScout might not be fully ready"

# Ensure Support Mailbox exists
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 1. Create the VALUABLE ticket (to be restored)
# We create it active, then delete it to move to trash
TARGET_SUBJECT="Signed Contract - Q3 2024"
TARGET_ID=$(create_conversation_via_orm "$TARGET_SUBJECT" "$MAILBOX_ID" "legal@partner.com" "" "Attached is the signed agreement for the Q3 partnership. Please countersign.")
# Soft delete it (move to Trash)
fs_tinker "\$c = \\App\\Conversation::find($TARGET_ID); if(\$c) { \$c->delete(); }"

echo "$TARGET_ID" > /tmp/target_id.txt
echo "Created Target Ticket (ID: $TARGET_ID) and moved to Trash"

# 2. Create JUNK tickets (to be purged)
JUNK1_ID=$(create_conversation_via_orm "SEO Proposal" "$MAILBOX_ID" "spam@marketing.com" "" "Rank #1 on Google with our services!")
fs_tinker "\$c = \\App\\Conversation::find($JUNK1_ID); if(\$c) { \$c->delete(); }"

JUNK2_ID=$(create_conversation_via_orm "You won!" "$MAILBOX_ID" "prize@winner.com" "" "Click here to claim your prize.")
fs_tinker "\$c = \\App\\Conversation::find($JUNK2_ID); if(\$c) { \$c->delete(); }"

JUNK3_ID=$(create_conversation_via_orm "Undelivered Mail" "$MAILBOX_ID" "daemon@server.com" "" "Delivery failed for message <12345>.")
fs_tinker "\$c = \\App\\Conversation::find($JUNK3_ID); if(\$c) { \$c->delete(); }"

# Store Junk IDs for export script to verify they are gone
echo "$JUNK1_ID,$JUNK2_ID,$JUNK3_ID" > /tmp/junk_ids.txt
echo "Created Junk Tickets (IDs: $JUNK1_ID, $JUNK2_ID, $JUNK3_ID) and moved to Trash"

# Clear cache to ensure UI reflects database state
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    # Start on Dashboard, let agent navigate to Trash/Deleted
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="