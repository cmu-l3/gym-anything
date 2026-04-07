#!/bin/bash
set -e
echo "=== Setting up bulk_onboard_clients_conditional task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Prepare the 'Clients' workspace
# Check if it exists; if so, delete it to ensure a clean state (remove old client folders)
if doc_exists "/default-domain/workspaces/Clients"; then
    echo "Cleaning up existing Clients workspace..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Clients"
    sleep 2
fi

# Create the empty Clients workspace
echo "Creating empty Clients workspace..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Clients" "Clients" "Workspace for client onboarding"

# 4. Create the input text file with client names
CLIENT_LIST="/home/ga/Documents/new_clients.txt"
mkdir -p "$(dirname "$CLIENT_LIST")"
cat > "$CLIENT_LIST" <<EOF
Riverfront Properties
TechGlobal LLC
Sarah Jenkins
EOF
chown ga:ga "$CLIENT_LIST"
chmod 644 "$CLIENT_LIST"
echo "Created $CLIENT_LIST"

# 5. Launch Firefox and navigate to the Workspaces list
# This forces the agent to navigate into 'Clients' themselves, verifying they find the right place.
if ! pgrep -f "firefox" > /dev/null; then
    open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces"
else
    navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces"
fi

# Ensure logged in
nuxeo_login

# 6. Capture initial state screenshot
sleep 2
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="