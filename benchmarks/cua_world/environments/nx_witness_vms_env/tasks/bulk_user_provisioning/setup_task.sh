#!/bin/bash
set -e
echo "=== Setting up Bulk User Provisioning Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Refresh auth token to ensure we can set up the environment
NX_TOKEN=$(refresh_nx_token)

# ==============================================================================
# 1. Create the Custom Role "Shift Supervisor"
# ==============================================================================
echo "Creating custom role 'Shift Supervisor'..."
# Check if it exists first to avoid error
EXISTING_ROLE=$(nx_api_get "/rest/v1/userRoles" | python3 -c "
import sys, json
roles = json.load(sys.stdin)
found = [r for r in roles if r.get('name') == 'Shift Supervisor']
print(found[0]['id'] if found else '')
" 2>/dev/null || echo "")

if [ -z "$EXISTING_ROLE" ]; then
    ROLE_PAYLOAD='{
      "name": "Shift Supervisor",
      "permissions": ["viewLogs", "viewArchive", "exportArchive"]
    }'
    nx_api_post "/rest/v1/userRoles" "$ROLE_PAYLOAD"
    echo "Custom role created."
else
    echo "Custom role already exists."
fi

# ==============================================================================
# 2. Create the "Pre-existing" user (Clark Kent)
# ==============================================================================
# We verify idempotency by ensuring this user is NOT updated to match the CSV
echo "Ensuring pre-existing user 'c.kent' exists with specific state..."

# Check if exists
EXISTING_USER_ID=$(get_user_by_name "c.kent" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [ -n "$EXISTING_USER_ID" ]; then
    echo "User c.kent exists, resetting state..."
    nx_api_delete "/rest/v1/users/${EXISTING_USER_ID}"
fi

# Create with "Live Viewer" role (id ending in ...3 usually, or just a standard ID)
# We use a standard ID or just let the system assign one, but we set a specific password
# and a role that is DIFFERENT from the CSV (CSV says 'Viewer', we set 'Live Viewer')
# Live Viewer ID is typically 00000000-0000-0000-0000-100000000003
LIVE_VIEWER_ID="00000000-0000-0000-0000-100000000003"

USER_PAYLOAD='{
  "name": "c.kent",
  "fullName": "Clark Kent",
  "email": "c.kent@dailyplanet.com",
  "password": "OriginalPassword1!",
  "userRoleId": "'$LIVE_VIEWER_ID'", 
  "isEnabled": true
}'
nx_api_post "/rest/v1/users" "$USER_PAYLOAD"

# ==============================================================================
# 3. Create the CSV file with "messy" data
# ==============================================================================
echo "Creating roster CSV..."
mkdir -p /home/ga/Documents

# Note: a.curry has spaces around " Viewer " to test trimming
# c.kent is in the CSV with "Viewer" role (conflict with existing "Live Viewer")
cat > /home/ga/Documents/security_roster.csv <<EOF
Username,FullName,Email,RoleName,Password
b.wayne,Bruce Wayne,b.wayne@gotham.sec,Shift Supervisor,BatM@n123
d.prince,Diana Prince,d.prince@gotham.sec,Advanced Viewer,W0nderW!
a.curry,Arthur Curry,a.curry@atlantis.net, Viewer ,Trident#5
c.kent,Clark Kent,c.kent@dailyplanet.com,Viewer,Krypt0n88
EOF

chown ga:ga /home/ga/Documents/security_roster.csv
chmod 644 /home/ga/Documents/security_roster.csv

# ==============================================================================
# 4. Environment State
# ==============================================================================
# Ensure Firefox is running (API docs or Users page)
ensure_firefox_running "https://localhost:7001/static/index.html#/users"
maximize_firefox

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="