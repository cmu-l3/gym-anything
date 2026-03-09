#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up restore_deleted_conversation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Ensure FreeScout is running =====
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "ERROR: FreeScout is not running (HTTP $HTTP_CODE)"
    cd /home/ga/freescout && docker-compose up -d
    sleep 30
fi

# ===== Create the "IT Infrastructure Support" mailbox =====
echo "Creating IT Infrastructure Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Infrastructure Support" "it-infra@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

if [ -z "$MAILBOX_ID" ] || [ "$MAILBOX_ID" = "0" ]; then
    echo "ERROR: Failed to create mailbox"
    exit 1
fi

# ===== Create a customer for the conversations =====
CUSTOMER_ID=$(fs_tinker "
\$c = \\App\\Customer::where('first_name', 'Marcus')->where('last_name', 'Chen')->first();
if (!\$c) {
    \$c = new \\App\\Customer();
    \$c->first_name = 'Marcus';
    \$c->last_name = 'Chen';
    \$c->save();
    \$email = new \\App\\Email();
    \$email->customer_id = \$c->id;
    \$email->email = 'mchen@acmecorp.net';
    \$email->save();
}
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')

echo "Customer ID: $CUSTOMER_ID"

# ===== Create several conversations in the mailbox (some active, one to be deleted) =====

# Active conversation 1
echo "Creating active conversations..."
CONV1_ID=$(create_conversation_via_orm \
    "VPN Tunnel Configuration - Remote Office Atlanta" \
    "$MAILBOX_ID" \
    "mchen@acmecorp.net" \
    "$CUSTOMER_ID" \
    "Hi team, we need to set up a new VPN tunnel to the Atlanta remote office. The ISP has provided the following details: Public IP 203.0.113.45, Subnet 10.50.0.0/24. Please configure the tunnel on our Palo Alto firewall.")

# Active conversation 2
CONV2_ID=$(create_conversation_via_orm \
    "Wireless AP Firmware Update Schedule - All Buildings" \
    "$MAILBOX_ID" \
    "mchen@acmecorp.net" \
    "$CUSTOMER_ID" \
    "We need to schedule firmware updates for all Aruba wireless access points across buildings A through D. Current firmware is 8.6.0.2 and we need to update to 8.10.0.6. Please propose a maintenance window.")

# THE conversation that will be deleted (target for restoration)
echo "Creating target conversation (to be deleted)..."
TARGET_CONV_ID=$(create_conversation_via_orm \
    "Cisco 2960X Switch Replacement - Building C Floor 3" \
    "$MAILBOX_ID" \
    "mchen@acmecorp.net" \
    "$CUSTOMER_ID" \
    "The Cisco 2960X switch in Building C, Floor 3 IDF closet has been experiencing intermittent port failures on interfaces Gi1/0/12 through Gi1/0/18. After diagnostics, the hardware team recommends a full replacement. The new switch (SN: FCW2345L0PQ) has arrived and the on-site technician from NetPro Solutions is scheduled for Thursday. Please ensure the running configuration is backed up and the replacement switch is pre-staged with VLAN assignments: VLAN 10 (Data), VLAN 20 (Voice), VLAN 30 (Management), VLAN 99 (Native).")
echo "Target Conv ID: $TARGET_CONV_ID"

if [ -z "$TARGET_CONV_ID" ] || [ "$TARGET_CONV_ID" = "0" ]; then
    echo "ERROR: Failed to create target conversation"
    exit 1
fi

# Save the target conversation ID for verification
echo "$TARGET_CONV_ID" > /tmp/target_conv_id.txt
echo "$MAILBOX_ID" > /tmp/target_mailbox_id.txt

# ===== Delete the target conversation =====
echo "Deleting target conversation (state -> 3)..."
fs_tinker "
\$conv = \\App\\Conversation::find($TARGET_CONV_ID);
if (\$conv) {
    \$conv->state = 3; // Deleted state
    \$conv->save();
    
    // Move to Deleted folder (type 110 is usually Trash/Deleted in FreeScout schema)
    // We try to find the folder of type 3 (Trash) or custom
    \$deletedFolder = \\App\\Folder::where('mailbox_id', $MAILBOX_ID)->where('type', 3)->first();
    
    if (\$deletedFolder) {
        \$conv->folder_id = \$deletedFolder->id;
        \$conv->save();
        \$deletedFolder->updateCounters();
    }
    
    // Update original folder counters
    \$folders = \\App\\Folder::where('mailbox_id', $MAILBOX_ID)->get();
    foreach (\$folders as \$f) { \$f->updateCounters(); }
    
    echo 'DELETED:OK state=' . \$conv->state;
} else {
    echo 'DELETED:FAIL conversation not found';
}
"

# Verify deletion
DELETED_STATE=$(fs_query "SELECT state FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null)
echo "Target conversation state after deletion: $DELETED_STATE"
echo "$DELETED_STATE" > /tmp/initial_conv_state.txt

if [ "$DELETED_STATE" != "3" ]; then
    echo "WARNING: Conversation state is $DELETED_STATE, expected 3 (Deleted). Forcing update."
    fs_query "UPDATE conversations SET state = 3 WHERE id = $TARGET_CONV_ID" 2>/dev/null
fi

# ===== Clear PHP/OPcache =====
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ===== Set up Firefox =====
echo "Navigating Firefox to FreeScout..."

# Kill existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the mailbox page
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="