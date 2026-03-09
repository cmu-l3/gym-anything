#!/bin/bash
set -e
echo "=== Setting up Configure Technician Availability task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Start SDP and wait for it to be ready
ensure_sdp_running

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt
# Record the specific "Tomorrow" date string (YYYY-MM-DD) for verification reference
date -d "tomorrow" +%Y-%m-%d > /tmp/target_date_str.txt
echo "Target Date: $(cat /tmp/target_date_str.txt)"

# 3. Generate API key for setup automation
echo "Generating API key..."
API_KEY=$(get_sdp_api_key_from_db)
if [ -z "$API_KEY" ]; then
    write_python_login_script
    API_KEY=$(generate_api_key_via_web)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Failed to generate API Key."
    # Fail gracefully? Or exit 1. We need setup to work.
    # If API key fails, we might rely on pre-existing data or try DB insert.
    echo "Attempting to continue without API key (using direct DB or manual agent actions)..."
fi

# 4. Create Technicians using Python + API
# We need John Doe and Sarah Smith to exist.
echo "Creating technicians..."
cat > /tmp/create_techs.py << PYEOF
import requests
import sys
import json

api_key = "$API_KEY"
base_url = "http://localhost:8080/api/v3/technicians"
headers = {"authtoken": api_key}

techs = [
    {"name": "John Doe", "email": "john.doe@example.com", "description": "Senior Technician"},
    {"name": "Sarah Smith", "email": "sarah.smith@example.com", "description": "Shift Lead"},
]

for tech in techs:
    # 1. Check if exists via search (simple check)
    # SDP API doesn't always have easy search, so we try to create and ignore 400s/errors
    
    input_data = {
        "technician": {
            "name": tech['name'],
            "email_id": tech['email'],
            "description": tech['description'],
            "status": { "name": "Active" },
            "login_name": tech['name'].replace(" ", "").lower(),
            "pwd": "Password123!"
        }
    }
    
    params = {"input_data": json.dumps(input_data)}
    try:
        print(f"Creating {tech['name']}...")
        response = requests.post(base_url, headers=headers, data=params, verify=False)
        print(f"Status: {response.status_code}, Response: {response.text[:100]}")
    except Exception as e:
        print(f"Failed to create {tech['name']}: {e}")
PYEOF

if [ -n "$API_KEY" ]; then
    python3 /tmp/create_techs.py
else
    # Fallback: Insert directly into DB if API fails (Advanced, skipping for safety in this template)
    echo "Skipping technician creation (API Key missing). Assuming they exist or agent will handle."
fi

# 5. Ensure Browser is open to Login Page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture Initial State Screenshot
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="