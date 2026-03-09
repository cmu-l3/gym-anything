#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Log Phone Conversation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Ensure FreeScout is running =====
cd /home/ga/freescout
docker-compose up -d 2>/dev/null || true
sleep 5

# Wait for FreeScout to be accessible
for i in {1..60}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "FreeScout is accessible (HTTP $HTTP_CODE)"
        break
    fi
    sleep 5
done

# ===== Create IT Support mailbox =====
echo "Creating IT Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# ===== Create customer David Chen =====
echo "Creating customer David Chen..."
EXISTING_CUSTOMER=$(find_customer_by_email "david.chen@acmecorp.com")
if [ -z "$EXISTING_CUSTOMER" ]; then
    fs_tinker "
\$customer = new \\App\\Customer();
\$customer->first_name = 'David';
\$customer->last_name = 'Chen';
\$customer->save();
\$email = new \\App\\Email();
\$email->customer_id = \$customer->id;
\$email->email = 'david.chen@acmecorp.com';
\$email->save();
echo 'CUSTOMER_ID:' . \$customer->id;
" > /tmp/customer_creation.log 2>&1
    CUSTOMER_ID=$(grep 'CUSTOMER_ID:' /tmp/customer_creation.log | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
else
    CUSTOMER_ID=$(echo "$EXISTING_CUSTOMER" | awk '{print $1}')
fi
echo "Customer ID: $CUSTOMER_ID"
echo "$CUSTOMER_ID" > /tmp/task_customer_id.txt

# ===== Record initial conversation counts =====
INITIAL_CONV_COUNT=$(get_conversation_count)
echo "$INITIAL_CONV_COUNT" > /tmp/initial_conv_count.txt
echo "Initial conversation count: $INITIAL_CONV_COUNT"

# Record initial phone conversation count specifically (Type 2 = Phone)
INITIAL_PHONE_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE type = 2" 2>/dev/null || echo "0")
echo "$INITIAL_PHONE_COUNT" > /tmp/initial_phone_count.txt
echo "Initial phone conversation count: $INITIAL_PHONE_COUNT"

# ===== Ensure Firefox is open and ready =====
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
wait_for_window "firefox\|Mozilla\|FreeScout" 30 || true

# Focus and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to FreeScout main page (ensure logged in)
navigate_to_url "http://localhost:8080"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "IT Support Mailbox ID: $MAILBOX_ID"
echo "Customer David Chen ID: $CUSTOMER_ID"
echo "Initial conversation count: $INITIAL_CONV_COUNT"
echo "Initial phone conversation count: $INITIAL_PHONE_COUNT"