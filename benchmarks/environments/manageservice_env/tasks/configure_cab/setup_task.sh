#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure CAB Task ==="

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Ensure SDP is running
ensure_sdp_running

# 3. Create Required Technicians via API
# We need these users to exist so the agent can select them.
echo "Creating prerequisite technicians..."

# Get API Key
API_KEY=$(get_sdp_api_key_from_db)
if [ -z "$API_KEY" ]; then
    echo "API Key not found in DB, attempting to generate via web login..."
    write_python_login_script
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Could not retrieve API key. Cannot create technicians."
    # We will try to proceed, maybe they exist, but this is risky.
else
    echo "Using API Key: ${API_KEY:0:5}..."
    
    # Function to create technician
    create_tech() {
        local name="$1"
        local email="$2"
        
        # Check if user exists in DB first to avoid API errors
        # Note: checking aaauser table or similar
        local exists_count=$(sdp_db_exec "SELECT count(*) FROM aaauser WHERE first_name = '${name%% *}' AND last_name = '${name#* }';" 2>/dev/null || echo "0")
        
        if [ "$exists_count" != "0" ]; then
            echo "Technician '$name' likely exists."
        else
            echo "Creating '$name'..."
            # Using v3 API
            curl -k -X POST "${SDP_BASE_URL}/api/v3/technicians" \
                -H "authtoken: $API_KEY" \
                -H "Content-Type: application/vnd.manageengine.sdp.v3+json" \
                -d "{
                    \"technician\": {
                        \"name\": \"$name\",
                        \"email_id\": \"$email\",
                        \"is_technician\": true,
                        \"status\": { \"name\": \"Active\" }
                    }
                }" > /dev/null 2>&1 || echo "API call failed for $name"
        fi
    }

    create_tech "David Chen" "david.chen@example.com"
    create_tech "Sarah Miller" "sarah.miller@example.com"
fi

# 4. Record Initial CAB count (Anti-gaming)
INITIAL_CAB_COUNT=$(sdp_db_exec "SELECT count(*) FROM cabdefinition;" 2>/dev/null || echo "0")
echo "$INITIAL_CAB_COUNT" > /tmp/initial_cab_count.txt

# 5. Launch Firefox to Login Page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture Initial State
sleep 5
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="