#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up reply_to_conversation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt
sleep 1

# ===== Ensure FreeScout is running =====
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "FreeScout not ready (HTTP $HTTP_CODE), waiting..."
    sleep 30
fi

# ===== Create mailbox "IT Support" =====
echo "Creating IT Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "it-support@helpdesk.local")
echo "IT Support mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# ===== Create customers =====
echo "Creating customers..."

# Rachel Morrison (target customer)
RACHEL_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Rachel';
\$c->last_name = 'Morrison';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'rachel.morrison@acmecorp.com';
\$e->save();
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')
echo "Rachel Morrison customer ID: $RACHEL_ID"

# Additional customers for realism
fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'David';
\$c->last_name = 'Chen';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'david.chen@acmecorp.com';
\$e->save();
" > /dev/null 2>&1

DAVID_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='david.chen@acmecorp.com' LIMIT 1" 2>/dev/null)

fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Sarah';
\$c->last_name = 'Nguyen';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'sarah.nguyen@acmecorp.com';
\$e->save();
" > /dev/null 2>&1

SARAH_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='sarah.nguyen@acmecorp.com' LIMIT 1" 2>/dev/null)

# ===== Create conversations =====
echo "Creating conversations..."

# Target conversation: VPN issue from Rachel
TARGET_CONV_ID=$(create_conversation_via_orm \
    "VPN Connection Dropping Intermittently" \
    "$MAILBOX_ID" \
    "rachel.morrison@acmecorp.com" \
    "$RACHEL_ID" \
    "Hi IT Support, I have been experiencing intermittent VPN disconnections over the past two days. The connection drops every 15-20 minutes, which is severely impacting my ability to work remotely. I am using the GlobalProtect VPN client version 5.2.8 on Windows 11. My home internet connection is stable (tested with speed test - 200 Mbps down, 50 Mbps up). The issue started after the last company-wide network maintenance window on Friday evening. Could you please help resolve this? It is urgent as I have client deliverables due this week. Thanks, Rachel Morrison")

echo "Target conversation ID: $TARGET_CONV_ID"
echo "$TARGET_CONV_ID" > /tmp/task_target_conv_id.txt

# Noise conversation 1: Password reset from David
NOISE1_ID=$(create_conversation_via_orm \
    "Cannot Reset Active Directory Password" \
    "$MAILBOX_ID" \
    "david.chen@acmecorp.com" \
    "$DAVID_ID" \
    "Hello, I tried to reset my AD password using the self-service portal but keep getting an error saying the password does not meet complexity requirements. I have tried multiple combinations. Can someone reset it manually? My username is dchen. Thanks, David Chen")

# Noise conversation 2: Software installation from Sarah
NOISE2_ID=$(create_conversation_via_orm \
    "Request for Adobe Creative Suite Installation" \
    "$MAILBOX_ID" \
    "sarah.nguyen@acmecorp.com" \
    "$SARAH_ID" \
    "Hi team, I need Adobe Creative Suite installed on my workstation (asset tag WS-4521) for an upcoming marketing project. My manager Lisa Park has approved the license. Could someone schedule a time to install it? I am available any afternoon this week. Thank you, Sarah Nguyen")

# Record initial thread count for target conversation
INITIAL_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id=$TARGET_CONV_ID" 2>/dev/null || echo "0")
echo "$INITIAL_THREAD_COUNT" > /tmp/task_initial_thread_count.txt

# Record initial conversation status
INITIAL_STATUS=$(fs_query "SELECT status FROM conversations WHERE id=$TARGET_CONV_ID" 2>/dev/null || echo "1")
echo "$INITIAL_STATUS" > /tmp/task_initial_status.txt

# Clear cache to ensure data appears
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ===== Ensure Firefox is open to FreeScout =====
echo "Setting up Firefox..."

# Kill existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 3

# Launch Firefox to FreeScout login
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
sleep 8

# Wait for Firefox window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout\|login"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="