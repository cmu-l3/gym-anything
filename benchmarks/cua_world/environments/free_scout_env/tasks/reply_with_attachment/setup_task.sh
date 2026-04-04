#!/bin/bash
set -e
echo "=== Setting up reply_with_attachment task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Create the dummy PDF file in Documents
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/VPN_Setup_Guide_v2.pdf << 'EOF'
%PDF-1.0
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 3 3]/Parent 2 0 R/Resources<<>>>>endobj
xref
0 4
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000111 00000 n
trailer<</Size 4/Root 1 0 R>>
startxref
190
%%EOF
# Set permissions so the agent user 'ga' owns it
chown ga:ga /home/ga/Documents/VPN_Setup_Guide_v2.pdf
chmod 644 /home/ga/Documents/VPN_Setup_Guide_v2.pdf

# 3. Ensure Mailbox Exists
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "support@company.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 4. Create Customer and Conversation via database/ORM
CUSTOMER_EMAIL="linda.chen@example.com"
SUBJECT="Need VPN instructions"
BODY="Hi IT,\n\nI'm trying to work from home but I can't figure out the VPN. Do you have a manual or instructions you can send me?\n\nThanks,\nLinda"

# Check if conversation already exists to avoid duplicates on retry
EXISTING_CONV=$(find_conversation_by_subject "$SUBJECT")

if [ -z "$EXISTING_CONV" ]; then
    # Create customer and conversation
    # We use a helper from task_utils.sh or do it manually if needed. 
    # task_utils.sh has create_conversation_via_orm which handles customer creation logic internally if ID not provided
    CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "" "$BODY")
    echo "Created new conversation ID: $CONV_ID"
else
    CONV_ID=$(echo "$EXISTING_CONV" | cut -f1)
    echo "Using existing conversation ID: $CONV_ID"
fi

echo "$CONV_ID" > /tmp/target_conversation_id.txt

# 5. Record initial thread count for this conversation
# This helps us detect if a NEW reply is added
INITIAL_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "0")
echo "$INITIAL_THREAD_COUNT" > /tmp/initial_thread_count.txt

# 6. Launch Firefox and navigate to the conversation
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    # Start Firefox maximized pointing to the specific conversation
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/conversation/$CONV_ID' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 60

# Maximize and focus
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="