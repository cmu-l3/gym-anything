#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Bulk Move Purchase Orders ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure 'Sales' mailbox exists (Destination)
SALES_MB_ID=$(ensure_mailbox_exists "Sales" "sales@helpdesk.local")
echo "Sales Mailbox ID: $SALES_MB_ID"

# 2. Ensure 'Support' mailbox exists (Source)
SUPPORT_MB_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Support Mailbox ID: $SUPPORT_MB_ID"

# 3. Create Target Conversations (Purchase Orders) in Support Mailbox
# We check if they exist first to avoid duplicates on retry
echo "Creating target conversations..."
create_conversation_via_orm "Purchase Order #3021 - Urgent" "$SUPPORT_MB_ID" "buyer1@retail.com" "" "Please process the attached PO for 50 units."
create_conversation_via_orm "Purchase Order #3022" "$SUPPORT_MB_ID" "buyer2@retail.com" "" "New order attached."
create_conversation_via_orm "Re: Purchase Order #3023" "$SUPPORT_MB_ID" "buyer3@retail.com" "" "Updated quantities for our order."
create_conversation_via_orm "Purchase Order #3024 - Q3 Restock" "$SUPPORT_MB_ID" "buyer4@retail.com" "" "Restocking order for Q3."
create_conversation_via_orm "Fwd: Purchase Order #3025" "$SUPPORT_MB_ID" "manager@internal.com" "" "Forwarding this PO that came to my personal email."

# 4. Create Distractor Conversations in Support Mailbox
# These should NOT be moved
echo "Creating distractor conversations..."
create_conversation_via_orm "Printer Jam in Accounting" "$SUPPORT_MB_ID" "acct@internal.com" "" "The Ricoh printer is jammed again."
create_conversation_via_orm "Login failed for VPN" "$SUPPORT_MB_ID" "remote@internal.com" "" "I cannot connect to the VPN gateway."
create_conversation_via_orm "Where is the coffee machine?" "$SUPPORT_MB_ID" "newhire@internal.com" "" "Silly question, but where is the break room?"

# Clear cache to ensure new conversations appear
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Launch Application
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$SUPPORT_MB_ID' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate if already open
    navigate_to_url "http://localhost:8080/mailbox/$SUPPORT_MB_ID"
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 30

# Ensure window is maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Capture initial state
take_screenshot "/tmp/task_initial_state.png"

echo "=== Setup Complete ==="