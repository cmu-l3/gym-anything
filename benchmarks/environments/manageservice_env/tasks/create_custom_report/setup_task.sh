#!/bin/bash
echo "=== Setting up Create Custom Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Get/Generate API Key for data population
echo "Retrieving API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "No API Key found, attempting to generate via python login script..."
    write_python_login_script
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "WARNING: Failed to get API Key. Sample data creation might fail if not done via SQL."
    # We will try SQL fallback or just proceed hoping data exists
fi

# 3. Create Sample Data (Requests)
echo "Creating sample requests..."
# We use a python script to inject data via API for realism, or SQL if API fails
cat > /tmp/create_sample_data.py << PYEOF
import requests
import json
import sys
import random
import time

api_key = "$API_KEY"
base_url = "http://localhost:8080/api/v3/requests"

# Sample data definitions
departments = ["Engineering", "HR", "IT", "Finance", "Marketing", "Facilities"]
priorities = ["High", "Medium", "Low", "Normal"]
statuses = ["Open", "Open", "Open", "On Hold", "Resolved", "Closed"] # Weighted towards Open

samples = [
    ("VPN connection drops intermittently", "High", "Open", "Engineering"),
    ("New laptop provisioning for marketing", "Medium", "Open", "HR"),
    ("Outlook not syncing emails", "High", "Open", "IT"),
    ("Request access to shared drive", "Low", "Open", "Finance"),
    ("Printer on 3rd floor jamming", "Normal", "On Hold", "Facilities"),
    ("Adobe Creative Cloud license renewal", "Medium", "Open", "Marketing"),
    ("Two-factor authentication failure", "High", "Open", "Engineering"),
    ("Conference room AV system no signal", "Normal", "Resolved", "IT"),
    ("SAP access provisioning", "Medium", "Open", "Finance"),
    ("Slow network speeds in Building B", "High", "Open", "IT"),
    ("Teams screen sharing fails", "Normal", "Closed", "Engineering"),
    ("Onboarding checklist execution", "Low", "Open", "HR")
]

headers = {"authtoken": api_key}

for subject, priority, status, dept in samples:
    # Construct input data (simplified for SDP API v3)
    data = {
        "request": {
            "subject": subject,
            "priority": {"name": priority},
            "status": {"name": status},
            "group": {"name": dept} # Using group as department proxy if dept not configured, or adjust based on schema
            # Note: In vanilla SDP, Department is a separate field, but often requires ID. 
            # We'll just set Subject/Priority/Status which are critical for the report.
        }
    }
    
    try:
        # Note: input_data param depends on specific SDP version, usually 'input_data' form param
        files = {'input_data': (None, json.dumps(data))}
        response = requests.post(base_url, headers=headers, files=files, verify=False, timeout=5)
        if response.status_code not in [200, 201]:
             print(f"Failed to create {subject}: {response.text}")
    except Exception as e:
        print(f"Error creating {subject}: {e}")

print("Sample data generation attempt complete.")
PYEOF

if [ -n "$API_KEY" ]; then
    python3 /tmp/create_sample_data.py > /tmp/data_generation.log 2>&1
else
    echo "Skipping API data generation (no key)."
fi

# 4. Record initial report count (Anti-gaming)
INITIAL_REPORT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM reportconfiguration;" "servicedesk")
echo "$INITIAL_REPORT_COUNT" > /tmp/initial_report_count.txt

# 5. Launch Firefox to Home Page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="