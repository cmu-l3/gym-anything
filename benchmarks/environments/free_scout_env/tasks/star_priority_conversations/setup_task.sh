#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up star_priority_conversations task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create "Network Support" mailbox
MAILBOX_ID=$(ensure_mailbox_exists "Network Support" "network-support@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# Helper to create customers
create_customer_record() {
    local first="$1"
    local last="$2"
    local email="$3"
    local result
    result=$(fs_tinker "
\$existing = \\App\\Email::where('email', '$email')->first();
if (\$existing) { echo 'CID:' . \$existing->customer_id; return; }
\$c = new \\App\\Customer();
\$c->first_name = '$first';
\$c->last_name = '$last';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = '$email';
\$e->save();
echo 'CID:' . \$c->id;
")
    echo "$result" | grep 'CID:' | sed 's/CID://' | tr -cd '0-9'
}

echo "Creating customers..."
C1=$(create_customer_record "James" "Rodriguez" "j.rodriguez@techcorp.net")
C2=$(create_customer_record "Sarah" "Chen" "s.chen@techcorp.net")
C3=$(create_customer_record "Michael" "Okafor" "m.okafor@techcorp.net")
C4=$(create_customer_record "Lisa" "Petrov" "l.petrov@techcorp.net")
C5=$(create_customer_record "David" "Kim" "d.kim@techcorp.net")

# Define conversations
declare -a SUBJECTS
declare -a BODIES
declare -a CUST_IDS

# The 3 target critical incidents
SUBJECTS[0]="Core Switch Failure - Building A"
BODIES[0]="The core switch in Building A MDF has gone down. Multiple floors are reporting complete loss of network connectivity. This is affecting approximately 200 users across Engineering and Product departments. SNMP traps show the switch stopped responding at 02:47 AM. Need immediate on-site response and vendor escalation."
CUST_IDS[0]="$C1"

SUBJECTS[1]="VPN Gateway Timeout Errors"
BODIES[1]="Users across the organization are reporting intermittent VPN disconnections and gateway timeout errors when connecting remotely. The issue started this morning around 6:15 AM EST. Approximately 85 remote workers are affected. Cisco AnyConnect logs show SSL handshake failures. This is blocking all remote work."
CUST_IDS[1]="$C2"

SUBJECTS[2]="DNS Resolution Failures Across Campus"
BODIES[2]="Multiple departments are reporting DNS resolution failures. Both internal domains (ad.techcorp.net) and external domains are intermittently failing to resolve. nslookup returns SERVFAIL for about 40% of queries. This appears to be campus-wide and is impacting all business operations including email, web apps, and file shares."
CUST_IDS[2]="$C3"

# Routine requests (distractors)
SUBJECTS[3]="Printer Not Connecting to Network"
BODIES[3]="The HP LaserJet Pro in room 205 is no longer appearing on the network. Users have tried power cycling but it still shows offline status. The printer was working fine yesterday. This is a shared printer for the finance team - about 8 people use it daily."
CUST_IDS[3]="$C4"

SUBJECTS[4]="New Employee Workstation Setup - Marketing Dept"
BODIES[4]="We have a new marketing coordinator starting next Monday (Emily Torres). Need a standard workstation setup with dual 24-inch monitors, Adobe Creative Cloud suite, Slack, and access to the Marketing shared drive on NAS. Desk location is 3rd floor, cube 312B. Please have everything ready by Friday EOD."
CUST_IDS[4]="$C5"

SUBJECTS[5]="Slow Internet Speed in Conference Room 3B"
BODIES[5]="Conference room 3B on the 2nd floor consistently has poor WiFi speeds during meetings. Users report video calls on Zoom and Teams dropping frequently and slow file access from the NAS. Speed tests show only 5-10 Mbps down when we should be getting 100+. The AP in the ceiling might need replacement or repositioning."
CUST_IDS[5]="$C1"

SUBJECTS[6]="Password Reset for VoIP Phone System"
BODIES[6]="The Cisco UCM admin password needs to be reset. The previous telecom admin (Mark Sullivan) left the company last month and we dont have the current credentials documented. We need access to add extensions for three new hires next week. This is not super urgent but needs to be done before Friday."
CUST_IDS[6]="$C2"

SUBJECTS[7]="Monitor Replacement Request - Accounting"
BODIES[7]="The left monitor at accounting desk 4A (Janet Wongs station) has developed a cluster of dead pixels in the center of the screen making it difficult to read spreadsheets. Current model is Dell U2419H 24 inch. Please arrange a replacement from inventory or order a new one if none available."
CUST_IDS[7]="$C3"

# Create conversations
STAR_TARGET_IDS=""
ALL_CONV_IDS=""

echo "Creating conversations..."
# Loop through all 8 conversations
for i in {0..7}; do
    CONV_ID=$(create_conversation_via_orm "${SUBJECTS[$i]}" "$MAILBOX_ID" "" "${CUST_IDS[$i]}" "${BODIES[$i]}")
    echo "  Created conversation $i: ID=$CONV_ID, Subject='${SUBJECTS[$i]}'"
    ALL_CONV_IDS="${ALL_CONV_IDS}${CONV_ID} "
    
    # Track the IDs of the first 3 (indices 0, 1, 2) which are the targets
    if [ "$i" -lt 3 ]; then
        STAR_TARGET_IDS="${STAR_TARGET_IDS}${CONV_ID} "
    fi
    sleep 0.5
done

# Save IDs for verification
echo "$STAR_TARGET_IDS" > /tmp/task_target_conv_ids.txt
echo "$ALL_CONV_IDS" > /tmp/task_all_conv_ids.txt

# Reset any stars in the system to ensure clean state (user_id=1 is admin)
fs_query "DELETE FROM conversation_folder JOIN folders ON conversation_folder.folder_id = folders.id WHERE folders.type = 25 AND folders.user_id = 1" 2>/dev/null || true

# Record initial starred count (should be 0)
# Folder type 25 is TYPE_STARRED in FreeScout
INITIAL_STARRED=$(fs_query "SELECT COUNT(cf.conversation_id) FROM conversation_folder cf JOIN folders f ON cf.folder_id = f.id WHERE f.type = 25 AND f.user_id = 1" 2>/dev/null || echo "0")
echo "$INITIAL_STARRED" > /tmp/initial_starred_count.txt
echo "Initial starred count: $INITIAL_STARRED"

# Clear cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Navigate Firefox to the Network Support mailbox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/${MAILBOX_ID}' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Ensure window is ready
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox

# Ensure we are at the right URL
navigate_to_url "http://localhost:8080/mailbox/${MAILBOX_ID}"
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="