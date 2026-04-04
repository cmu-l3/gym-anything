#!/bin/bash
echo "=== Setting up add_worklog_to_request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure ServiceDesk Plus is running
ensure_sdp_running

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Create the Target Request via API
# We need to generate an API key first if one doesn't exist
echo "Getting API Key..."
API_KEY=$(get_sdp_api_key_from_db)

if [ -z "$API_KEY" ]; then
    echo "Generating API key via web login..."
    generate_api_key_via_web
    API_KEY=$(get_sdp_api_key_from_db)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Failed to obtain API Key. Creating request via DB fallback..."
    # Fallback SQL insert if API fails (Basic insert to ensure task functionality)
    # Note: This is risky as it skips triggers, but acceptable for setup fallback
    REQ_ID=$(date +%s)
    sdp_db_exec "INSERT INTO WorkOrder (WORKORDERID, TITLE, DESCRIPTION, STATUSID, PRIORITYID, CREATEDTIME, REQUESTERID) VALUES ($REQ_ID, 'VPN disconnects intermittently for remote user', 'User reports frequent disconnects when working from home.', 3, 3, $(date +%s000), 2);"
    echo "$REQ_ID" > /tmp/target_request_id.txt
else
    # Create Request via API
    echo "Creating request via API..."
    python3 -c "
import requests, json, sys
url = '${SDP_BASE_URL}/api/v3/requests'
headers = {'TECHNICIAN_KEY': '$API_KEY'}
data = {
    'request': {
        'subject': 'VPN disconnects intermittently for remote user',
        'description': 'User reports frequent disconnects when working from home.',
        'priority': {'name': 'High'},
        'status': {'name': 'Open'}
    }
}
try:
    response = requests.post(url, headers=headers, data={'input_data': json.dumps(data)}, verify=False)
    if response.status_code in [200, 201]:
        resp_json = response.json()
        req_id = resp_json.get('request', {}).get('id')
        if req_id:
            print(req_id)
            sys.exit(0)
    print('API Error:', response.text)
    sys.exit(1)
except Exception as e:
    print(e)
    sys.exit(1)
" > /tmp/created_req_id.txt

    if [ -s /tmp/created_req_id.txt ]; then
        cp /tmp/created_req_id.txt /tmp/target_request_id.txt
        echo "Request created successfully. ID: $(cat /tmp/target_request_id.txt)"
    else
        echo "Failed to create request via API."
        exit 1
    fi
fi

# 4. Record Initial Worklog Count
TARGET_ID=$(cat /tmp/target_request_id.txt)
# Worklogs are linked via WorkOrderToCharge -> ChargesTable
INITIAL_WL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM WorkOrderToCharge WHERE WORKORDERID=$TARGET_ID" 2>/dev/null || echo "0")
echo "$INITIAL_WL_COUNT" > /tmp/initial_worklog_count.txt

# 5. Open Firefox to the Request
echo "Launching Firefox..."
REQUEST_URL="${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${TARGET_ID}"
ensure_firefox_on_sdp "$REQUEST_URL"

# 6. Capture Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Request ID: $TARGET_ID"