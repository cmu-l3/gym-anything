#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up close_conversation task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ===== Ensure FreeScout is running =====
echo "Checking FreeScout availability..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "FreeScout is available (HTTP $HTTP_CODE)"
        break
    fi
    sleep 2
done

# ===== Create Data =====

# 1. Create Mailbox
echo "Creating AV Equipment Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "AV Equipment Support" "av-support@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

if [ -z "$MAILBOX_ID" ] || [ "$MAILBOX_ID" = "0" ]; then
    echo "ERROR: Failed to create mailbox"
    # Fallback to default mailbox if creation fails
    MAILBOX_ID="1"
fi

# 2. Create Customer
echo "Creating customer Marcus Reed..."
CUSTOMER_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Marcus';
\$c->last_name = 'Reed';
\$c->save();
\$email = new \\App\\Email();
\$email->customer_id = \$c->id;
\$email->email = 'marcus.reed@brightwavemedia.com';
\$email->save();
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')
echo "Customer ID: $CUSTOMER_ID"

# 3. Create Conversation
echo "Creating conversation..."
CONV_SUBJECT="Projector installation request for Conference Room B - Building 4"
CONV_BODY="Hi,

We need a new Epson EB-L265F laser projector installed in Conference Room B on the 4th floor of Building 4. The room currently has an old ceiling-mounted unit that needs to be removed first.

Requirements:
- Remove existing BenQ projector and ceiling mount
- Install new Epson EB-L265F with adjustable ceiling mount
- Run HDMI 2.0 cable from the floor box to the projector (approx 8 meters)
- Configure lens shift and keystone for the 120-inch screen
- Test with the room's Crestron control system
- Dispose of old equipment properly

The room is available all day Thursday and Friday this week. Please confirm scheduling.

Thanks,
Marcus Reed
Facilities Coordinator
Brightwave Media"

CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "marcus.reed@brightwavemedia.com" "$CUSTOMER_ID" "$CONV_BODY")
echo "Conversation ID: $CONV_ID"

if [ -z "$CONV_ID" ] || [ "$CONV_ID" = "0" ]; then
    echo "ERROR: Failed to create conversation"
    exit 1
fi

# 4. Ensure Initial State (Active)
# Status: 1=Active, 2=Pending, 3=Closed, 4=Spam
fs_query "UPDATE conversations SET status = 1, state = 1 WHERE id = $CONV_ID" 2>/dev/null || true

# Record ID and initial status for verification
echo "$CONV_ID" > /tmp/target_conv_id.txt
INITIAL_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $CONV_ID" 2>/dev/null)
echo "$INITIAL_STATUS" > /tmp/initial_conv_status.txt
echo "Initial conversation status: $INITIAL_STATUS"

# Clear cache to ensure UI reflects DB changes
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ===== Setup Firefox =====
echo "Setting up Firefox..."
# Kill any existing instances
pkill -f firefox || true
sleep 1

# Start Firefox pointing to the mailbox or dashboard
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Login if needed (using helper from task_utils)
ensure_logged_in

# Navigate specifically to the mailbox to ensure visibility
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="