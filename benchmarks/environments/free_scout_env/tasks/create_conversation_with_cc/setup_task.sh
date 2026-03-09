#!/bin/bash
set -e
echo "=== Setting up create_conversation_with_cc task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Ensure FreeScout is running =====
cd /home/ga/freescout
if ! docker ps | grep -q freescout-app; then
    echo "Starting FreeScout containers..."
    docker-compose up -d
    sleep 30
fi

# Wait for FreeScout to be responsive
for i in {1..60}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "FreeScout is ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 5
done

# ===== Create "AV Support" mailbox =====
echo "Creating AV Support mailbox..."
AV_MAILBOX_ID=$(ensure_mailbox_exists "AV Support" "avsupport@lakewood-univ.edu")
echo "AV Support mailbox ID: $AV_MAILBOX_ID"
echo "$AV_MAILBOX_ID" > /tmp/av_mailbox_id.txt

# ===== Create customer: Prof. Martinez =====
echo "Creating customer Prof. Martinez..."
# Check if customer exists first
EXISTING_CUSTOMER=$(find_customer_by_email "prof.martinez@lakewood-univ.edu")

if [ -z "$EXISTING_CUSTOMER" ]; then
    # Create via Tinker for reliability
    fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Elena';
\$c->last_name = 'Martinez';
\$c->save();
\$email = new \\App\\Email();
\$email->customer_id = \$c->id;
\$email->email = 'prof.martinez@lakewood-univ.edu';
\$email->type = 'work';
\$email->save();
echo 'CUSTOMER_ID:' . \$c->id;
" > /tmp/customer_create_output.txt 2>&1
    CUSTOMER_ID=$(cat /tmp/customer_create_output.txt | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
    echo "Created customer ID: $CUSTOMER_ID"
else
    CUSTOMER_ID=$(echo "$EXISTING_CUSTOMER" | awk '{print $1}')
    echo "Customer already exists with ID: $CUSTOMER_ID"
fi
echo "$CUSTOMER_ID" > /tmp/customer_id.txt

# ===== Record initial counts =====
INITIAL_CONV_COUNT=$(get_conversation_count)
echo "$INITIAL_CONV_COUNT" > /tmp/initial_conv_count.txt
echo "Initial conversation count: $INITIAL_CONV_COUNT"

# ===== Ensure Firefox is running and navigated =====
echo "Setting up Firefox..."
pkill -f firefox || true
sleep 3

# Launch Firefox
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
sleep 8

# Wait for Firefox window
WAIT_FF=0
while [ $WAIT_FF -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
    WAIT_FF=$((WAIT_FF + 2))
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Login if needed
ensure_logged_in

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="