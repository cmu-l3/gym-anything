#!/bin/bash
set -e
echo "=== Setting up bulk close conversations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Create mailbox =====
echo "Creating IT Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# ===== Create customers =====
echo "Creating customers..."
# We create distinct customers so the avatars/names look realistic in the list
fs_tinker "
\$customers = [
    ['Mark', 'Thompson', 'mark.thompson@acmecorp.com'],
    ['Lisa', 'Rodriguez', 'lisa.rodriguez@acmecorp.com'],
    ['James', 'Smith', 'james.smith@acmecorp.com'],
    ['Rachel', 'Kim', 'rachel.kim@acmecorp.com'],
    ['David', 'Patel', 'david.patel@acmecorp.com']
];

foreach (\$customers as \$c_data) {
    \$c = new \\App\\Customer();
    \$c->first_name = \$c_data[0];
    \$c->last_name = \$c_data[1];
    \$c->save();
    \$e = new \\App\\Email();
    \$e->customer_id = \$c->id;
    \$e->email = \$c_data[2];
    \$e->save();
}
" > /dev/null 2>&1

sleep 2

# ===== Create 5 conversations =====
echo "Creating conversations..."

# Helper to get customer ID by email
get_cid() {
    fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id=e.customer_id WHERE e.email='$1' LIMIT 1" 2>/dev/null
}

C1_ID=$(get_cid "mark.thompson@acmecorp.com")
C2_ID=$(get_cid "lisa.rodriguez@acmecorp.com")
C3_ID=$(get_cid "james.smith@acmecorp.com")
C4_ID=$(get_cid "rachel.kim@acmecorp.com")
C5_ID=$(get_cid "david.patel@acmecorp.com")

# Conversation 1 - RESOLVED (Target to close)
CONV1_ID=$(create_conversation_via_orm "Printer driver installed successfully" "$MAILBOX_ID" "mark.thompson@acmecorp.com" "$C1_ID" "Hi, the printer driver for the HP LaserJet 4050 has been installed on my workstation. Everything is printing correctly now. Thank you for your help!")

# Conversation 2 - RESOLVED (Target to close)
CONV2_ID=$(create_conversation_via_orm "VPN access restored for remote team" "$MAILBOX_ID" "lisa.rodriguez@acmecorp.com" "$C2_ID" "The VPN access issue for the remote team has been resolved. All 12 team members can now connect successfully using the new certificates. Thanks for the quick turnaround.")

# Conversation 3 - RESOLVED (Target to close)
CONV3_ID=$(create_conversation_via_orm "Password reset completed for jsmith" "$MAILBOX_ID" "james.smith@acmecorp.com" "$C3_ID" "My password has been reset and I can log into all systems now. The MFA token is also working. Appreciate the assistance.")

# Conversation 4 - ACTIVE (Keep open)
CONV4_ID=$(create_conversation_via_orm "Ongoing network latency in Building C" "$MAILBOX_ID" "rachel.kim@acmecorp.com" "$C4_ID" "We are still experiencing intermittent network latency on the 3rd floor of Building C. Download speeds drop to under 1 Mbps during peak hours.")

# Conversation 5 - ACTIVE (Keep open)
CONV5_ID=$(create_conversation_via_orm "New laptop request for onboarding" "$MAILBOX_ID" "david.patel@acmecorp.com" "$C5_ID" "We have 3 new hires starting on Monday. They each need a Dell Latitude 5540 with 16GB RAM, pre-loaded with the standard software image.")

echo "Conversations created:"
echo "  To Close: $CONV1_ID, $CONV2_ID, $CONV3_ID"
echo "  Keep Open: $CONV4_ID, $CONV5_ID"

# Store IDs for export script
echo "$CONV1_ID" > /tmp/conv_to_close_1.txt
echo "$CONV2_ID" > /tmp/conv_to_close_2.txt
echo "$CONV3_ID" > /tmp/conv_to_close_3.txt
echo "$CONV4_ID" > /tmp/conv_keep_open_1.txt
echo "$CONV5_ID" > /tmp/conv_keep_open_2.txt

# Ensure database timestamps are strictly in the past (to allow 'updated_at' checks)
fs_query "UPDATE conversations SET updated_at = DATE_SUB(NOW(), INTERVAL 1 HOUR), created_at = DATE_SUB(NOW(), INTERVAL 1 HOUR)" 2>/dev/null || true

# Clear cache to ensure UI reflects database
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# ===== Setup Firefox =====
echo "Navigating Firefox to IT Support mailbox..."

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/${MAILBOX_ID}' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|freescout" 30
focus_firefox

navigate_to_url "http://localhost:8080/mailbox/${MAILBOX_ID}"
sleep 3

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="