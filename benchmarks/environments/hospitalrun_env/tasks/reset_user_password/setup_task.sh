#!/bin/bash
echo "=== Setting up reset_user_password task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure HospitalRun and CouchDB are up
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Seed Users (Target + Noise)
echo "Seeding user data..."

# Helper to create a user in _users DB
create_user() {
    local username="$1"
    local password="$2"
    local fullname="$3"
    local roles="$4" # JSON array string like '["role1", "role2"]'
    
    # Calculate doc ID
    local doc_id="org.couchdb.user:${username}"
    
    # Check if exists to get rev (for update/delete)
    local rev
    rev=$(curl -s "http://couchadmin:test@localhost:5984/_users/${doc_id}" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))" 2>/dev/null || echo "")

    # Construct JSON payload
    # Note: 'type': 'user' is required. 'roles' must include 'user' for HospitalRun access usually.
    local payload
    if [ -n "$rev" ]; then
        # If exists, we update it (resetting to known state)
        payload=$(cat <<EOF
{
  "_id": "${doc_id}",
  "_rev": "${rev}",
  "name": "${username}",
  "password": "${password}",
  "fullname": "${fullname}",
  "roles": ${roles},
  "type": "user"
}
EOF
)
    else
        payload=$(cat <<EOF
{
  "_id": "${doc_id}",
  "name": "${username}",
  "password": "${password}",
  "fullname": "${fullname}",
  "roles": ${roles},
  "type": "user"
}
EOF
)
    fi

    curl -s -X PUT "http://couchadmin:test@localhost:5984/_users/${doc_id}" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null
    
    echo "Seeded user: $username ($fullname)"
}

# Seed the TARGET user with an OLD password
create_user "dr_amani" "old_pass_forgotten" "Amani Al-Fayed" '["Doctor", "Healer", "user"]'

# Seed NOISE users to populate the list
create_user "nurse_betty" "nurse123" "Betty Cooper" '["Nurse", "user"]'
create_user "clerk_john" "clerk123" "John Smith" '["Clerk", "user"]'
create_user "dr_house" "house123" "Gregory House" '["Doctor", "user"]'
create_user "admin_support" "support123" "IT Support" '["System Administrator", "admin", "user"]'

# 3. Prepare Browser
echo "Ensuring Firefox is ready..."
# We use the shared helper to ensure hradmin is logged in
ensure_hospitalrun_logged_in

# 4. Navigate to a neutral starting page (e.g., Dashboard or Users list)
# Let's start at the Users list so the agent sees the directory immediately? 
# Or start at Dashboard to force navigation. Task description says "Navigate to...", so Dashboard is better.
# However, to be nice, let's start at the main menu.
navigate_firefox_to "http://localhost:3000"

# Wait for UI to settle
sleep 5

# 5. Capture Initial State
take_screenshot /tmp/reset_password_initial.png
date +%s > /tmp/task_start_time.txt

# Record the initial revision of the target user doc to detect changes
curl -s "http://couchadmin:test@localhost:5984/_users/org.couchdb.user:dr_amani" > /tmp/initial_target_user.json

echo "=== Setup Complete ==="
echo "Target User: dr_amani (Amani Al-Fayed)"
echo "Goal: Reset password to 'WelcomeBack2026!'"