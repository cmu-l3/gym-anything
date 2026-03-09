#!/bin/bash
echo "=== Exporting Configure Closure Policy results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare the verification script
# This script runs inside the container to test the API and check the DB
cat > /tmp/verify_internal.py << 'PYEOF'
import json
import os
import sys
import requests
import subprocess
import time

# Disable warnings for self-signed certs
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

RESULT = {
    "api_connection": False,
    "policy_active_negative_test": False, # Did it block invalid close?
    "policy_valid_positive_test": False,  # Did it allow valid close?
    "auto_close_enabled": False,
    "auto_close_days": -1,
    "mandatory_fields_detected": [],
    "error": None
}

def get_api_key():
    """Retrieve API key directly from DB using subprocess."""
    # Try the query for SDP 14+
    cmd = "psql -h 127.0.0.1 -p 65432 -U postgres -d servicedesk -t -A -c \"SELECT auth_token FROM adsauthtokens WHERE user_id = (SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator' LIMIT 1) ORDER BY created_time DESC LIMIT 1;\""
    try:
        key = subprocess.check_output(cmd, shell=True).decode().strip()
        if key: return key
    except:
        pass
    
    # Fallback for older SDP
    cmd = "psql -h 127.0.0.1 -p 65432 -U postgres -d servicedesk -t -A -c \"SELECT auth_token FROM adskeybasedauthcredentials WHERE auth_credential_id = (SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator' LIMIT 1) LIMIT 1;\""
    try:
        key = subprocess.check_output(cmd, shell=True).decode().strip()
        if key: return key
    except:
        pass
    return None

def check_auto_close_db():
    """Check auto-close settings in DB."""
    # Query GlobalConfig or similar table for 'woms_close_resolved_requests' or similar
    # Since exact param name varies, we check a few common ones
    queries = [
        "SELECT paramvalue FROM globalconfig WHERE parameter='CLOSERESOLVEDWORKORDERS'",
        "SELECT paramvalue FROM globalconfig WHERE parameter='CLOSE_RESOLVED_WO_DAYS'"
    ]
    
    # Try to find if enabled
    try:
        cmd_enable = "psql -h 127.0.0.1 -p 65432 -U postgres -d servicedesk -t -A -c \"SELECT paramvalue FROM globalconfig WHERE parameter='CLOSERESOLVEDWORKORDERS';\""
        enabled_val = subprocess.check_output(cmd_enable, shell=True).decode().strip()
        if enabled_val.lower() == 'true':
            RESULT["auto_close_enabled"] = True
    except:
        pass

    # Try to find days
    try:
        cmd_days = "psql -h 127.0.0.1 -p 65432 -U postgres -d servicedesk -t -A -c \"SELECT paramvalue FROM globalconfig WHERE parameter='CLOSE_RESOLVED_WO_DAYS';\""
        days_val = subprocess.check_output(cmd_days, shell=True).decode().strip()
        if days_val:
            RESULT["auto_close_days"] = int(days_val)
    except:
        pass

def test_closure_policy(api_key):
    base_url = "https://localhost:8080/api/v3"
    headers = {"AUTHTOKEN": api_key, "Content-Type": "application/x-www-form-urlencoded"}
    
    # 1. Create a barebones request (Subject only)
    input_data = {
        "request": {
            "subject": "Verification Test Request " + str(time.time()),
            "status": {"name": "Open"}
        }
    }
    
    try:
        create_resp = requests.post(
            f"{base_url}/requests", 
            headers=headers, 
            data={"input_data": json.dumps(input_data)},
            verify=False
        )
        
        if create_resp.status_code not in [200, 201]:
            RESULT["error"] = f"Failed to create test request: {create_resp.text}"
            return

        request_id = create_resp.json().get("request", {}).get("id")
        if not request_id:
            RESULT["error"] = "No request ID returned"
            return
            
        print(f"Created test request ID: {request_id}")
        
        # 2. NEGATIVE TEST: Attempt to close without mandatory fields
        # Try to set status to 'Closed'
        update_data = {
            "request": {
                "status": {"name": "Closed"}
            }
        }
        
        close_resp = requests.put(
            f"{base_url}/requests/{request_id}",
            headers=headers,
            data={"input_data": json.dumps(update_data)},
            verify=False
        )
        
        # If policy is active, this SHOULD fail or return a validation error
        # SDP usually returns 200/400 but the response body contains failure status if validation fails
        resp_json = close_resp.json()
        status_code = resp_json.get("response_status", {}).get("status_code")
        
        print(f"Negative test response: {json.dumps(resp_json)}")
        
        # We expect failure if policy is working
        if status_code != 2000: # 2000 is usually success in v3 API
            RESULT["policy_active_negative_test"] = True
            msgs = resp_json.get("response_status", {}).get("messages", [])
            for m in msgs:
                if "category" in m.get("message", "").lower():
                    RESULT["mandatory_fields_detected"].append("Category")
                if "priority" in m.get("message", "").lower():
                    RESULT["mandatory_fields_detected"].append("Priority")
                if "resolution" in m.get("message", "").lower():
                    RESULT["mandatory_fields_detected"].append("Resolution")
        else:
            # It succeeded, meaning policy is NOT active
            RESULT["policy_active_negative_test"] = False
            
        # 3. POSITIVE TEST: Fill fields and close
        # Update with Category, Priority, Resolution
        # Note: We need valid IDs or Names. Using defaults usually available.
        
        # First, add a resolution
        res_data = {
            "resolution": {
                "content": "Fixed via verification script."
            }
        }
        requests.post(
            f"{base_url}/requests/{request_id}/resolution",
            headers=headers,
            data={"input_data": json.dumps(res_data)},
            verify=False
        )
        
        # Update request fields
        update_fields = {
            "request": {
                "category": {"name": "Hardware"}, # Assumes default data
                "priority": {"name": "High"},     # Assumes default data
                "status": {"name": "Closed"}
            }
        }
        
        final_resp = requests.put(
            f"{base_url}/requests/{request_id}",
            headers=headers,
            data={"input_data": json.dumps(update_fields)},
            verify=False
        )
        
        final_json = final_resp.json()
        if final_json.get("response_status", {}).get("status_code") == 2000:
            RESULT["policy_valid_positive_test"] = True
        else:
            print(f"Positive test failed: {final_json}")

    except Exception as e:
        RESULT["error"] = str(e)

def main():
    try:
        # Check DB config first
        check_auto_close_db()
        
        # Get API key
        api_key = get_api_key()
        if not api_key:
            RESULT["error"] = "Could not retrieve API key"
        else:
            RESULT["api_connection"] = True
            test_closure_policy(api_key)
            
    except Exception as e:
        RESULT["error"] = f"Top level error: {str(e)}"
    
    # Save result
    with open("/tmp/task_result.json", "w") as f:
        json.dump(RESULT, f)

if __name__ == "__main__":
    main()
PYEOF

# Run the python verification script
python3 /tmp/verify_internal.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Internal verification complete. Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="