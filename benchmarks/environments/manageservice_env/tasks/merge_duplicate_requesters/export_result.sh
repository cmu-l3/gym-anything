#!/bin/bash
set -e
echo "=== Exporting Merge Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for State Verification
# We need to check:
# A. Is "Cameron Howe" gone or inactive?
# B. Is "C. Howe" active?
# C. Is the ticket "BIOS firmware update..." assigned to "C. Howe"?

# Use psql via sdp_db_exec
# Tables: aaauser (base user), aaalogin (login), sduser (service desk extensions), 
# workorder (tickets), workorderstates (ticket status)

# Get User IDs by Name/Email
# Note: In SDP, when users are merged, the old user record in 'aaauser' might be deleted 
# or status changed in 'sduser'/'aaauserstatus'. Usually deleted or marked 'RESIGNED'.

echo "Querying database..."

# Function to run query and return JSON-friendly string or number
run_query() {
    sdp_db_exec "$1" "servicedesk"
}

# Check for Secondary User (Cameron Howe)
# We expect this to be 0 (deleted) or have status 'RESIGNED'/'DELETED'
# Querying count of active users with this email
OLD_USER_COUNT=$(run_query "SELECT COUNT(*) FROM aaauser a JOIN aaausercontactinfo aci ON a.user_id=aci.user_id JOIN aaacontactinfo c ON aci.contactinfo_id=c.contactinfo_id WHERE LOWER(c.emailid) = 'cameron@mutiny.com'")

# Check for Primary User (C. Howe)
# Expect count 1
NEW_USER_COUNT=$(run_query "SELECT COUNT(*) FROM aaauser a JOIN aaausercontactinfo aci ON a.user_id=aci.user_id JOIN aaacontactinfo c ON aci.contactinfo_id=c.contactinfo_id WHERE LOWER(c.emailid) = 'chowe@mutiny.com'")

# Get ID of Primary User
NEW_USER_ID=$(run_query "SELECT a.user_id FROM aaauser a JOIN aaausercontactinfo aci ON a.user_id=aci.user_id JOIN aaacontactinfo c ON aci.contactinfo_id=c.contactinfo_id WHERE LOWER(c.emailid) = 'chowe@mutiny.com' LIMIT 1")

# Check Ticket Assignment
# Find ticket by subject and get its requester_id
TICKET_REQUESTER_ID=$(run_query "SELECT requester_id FROM workorder WHERE title LIKE '%BIOS firmware update for Mutiny mainframes%' LIMIT 1")
TICKET_EXISTS=$(run_query "SELECT COUNT(*) FROM workorder WHERE title LIKE '%BIOS firmware update for Mutiny mainframes%'")

# Check if ticket requester matches new user
TICKET_CORRECTLY_ASSIGNED="false"
if [ -n "$TICKET_REQUESTER_ID" ] && [ -n "$NEW_USER_ID" ]; then
    if [ "$TICKET_REQUESTER_ID" = "$NEW_USER_ID" ]; then
        TICKET_CORRECTLY_ASSIGNED="true"
    fi
fi

# Anti-gaming: Check timestamp of ticket modification/merge?
# Hard to get exact merge time from DB easily without diving deep into history tables.
# We rely on the state: Old Gone + New Has Ticket.

# 3. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "old_user_count": ${OLD_USER_COUNT:-0},
    "new_user_count": ${NEW_USER_COUNT:-0},
    "new_user_id": "${NEW_USER_ID:-0}",
    "ticket_exists": ${TICKET_EXISTS:-0},
    "ticket_requester_id": "${TICKET_REQUESTER_ID:-0}",
    "ticket_correctly_assigned": $TICKET_CORRECTLY_ASSIGNED,
    "timestamp": "$(date +%s)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json