#!/bin/bash
echo "=== Exporting Configure Business Rule result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Write verification script
# This script logs in, creates a test ticket, checks the result, and queries the DB
write_python_login_script

cat > /tmp/verify_rule.py << 'PYEOF'
import sys
import json
import requests
import time
import subprocess
sys.path.append('/tmp')
from sdp_login import login, BASE

def check_db_rule():
    """Check if the rule exists in the DB by name."""
    try:
        # We use the sdp_db_exec utility via subprocess
        cmd = ["bash", "-c", "source /workspace/scripts/task_utils.sh && sdp_db_exec \"SELECT rulename FROM businessrule WHERE rulename ILIKE '%Auto-Route Network%'\""]
        result = subprocess.check_output(cmd).decode('utf-8').strip()
        return len(result) > 0, result
    except Exception as e:
        return False, str(e)

def run_functional_test():
    """Create a ticket and see if it gets routed."""
    s = requests.Session()
    if not login(s):
        return {"error": "Login failed"}
    
    print("Logged in. creating test request...")
    
    # Create a request using the default servlet or API
    # Using the standard servlet for adding requests
    # URL: /AddWorkOrder.do
    
    # First, get the 'add request' page to get any CSRF tokens if needed
    # SDP is often lenient on localhost/internal
    
    # We will try the API v3 if available, or v1
    # Generate API key
    try:
        # Attempt to get API key from DB directly
        cmd = ["bash", "-c", "source /workspace/scripts/task_utils.sh && get_sdp_api_key_from_db"]
        api_key = subprocess.check_output(cmd).decode('utf-8').strip()
    except:
        api_key = ""

    ticket_subject = "Urgent: Network connectivity failure in HR"
    
    created_request = None
    
    if api_key:
        print(f"Using API Key: {api_key[:5]}...")
        # V3 API
        headers = {'TECHNICIAN_KEY': api_key}
        data = {
            "request": {
                "subject": ticket_subject,
                "description": "Testing automation rule",
                "requester": {"name": "Administrator"}
            }
        }
        
        # Try to create request
        r = s.post(f"{BASE}/api/v3/requests", headers=headers, data={'input_data': json.dumps(data)}, verify=False)
        if r.status_code in [200, 201]:
            resp_json = r.json()
            if 'request' in resp_json:
                created_request = resp_json['request']
            elif 'response_status' in resp_json and resp_json['response_status']['status_code'] == 200:
                 # Sometimes structure varies
                 created_request = resp_json.get('request', {})
    
    # If API failed or no key, try form submission (harder, skipping for reliability)
    # If we can't create a ticket, we can't verify functionality, but we can still check DB.
    
    test_result = {
        "ticket_created": False,
        "routed_correctly": False,
        "details": {}
    }
    
    if created_request:
        req_id = created_request.get('id')
        print(f"Request created: {req_id}")
        test_result["ticket_created"] = True
        
        # Wait for rule to process (usually instant, but safe wait)
        time.sleep(2)
        
        # Fetch details
        r = s.get(f"{BASE}/api/v3/requests/{req_id}", headers=headers, verify=False)
        if r.status_code == 200:
            details = r.json().get('request', {})
            test_result["details"] = {
                "priority": details.get('priority', {}).get('name'),
                "group": details.get('group', {}).get('name'),
                "category": details.get('category', {}).get('name'),
                "subcategory": details.get('subcategory', {}).get('name')
            }
            
            # Check correctness
            prio_match = (test_result["details"]["priority"] == "High")
            group_match = (test_result["details"]["group"] == "Network Support")
            cat_match = (test_result["details"]["category"] == "Network")
            
            test_result["routed_correctly"] = (prio_match and group_match and cat_match)
    
    return test_result

def main():
    rule_exists, rule_name = check_db_rule()
    func_test = run_functional_test()
    
    result = {
        "rule_exists_in_db": rule_exists,
        "rule_name_db": rule_name,
        "functional_test": func_test,
        "timestamp": time.time()
    }
    
    with open("/tmp/rule_verification.json", "w") as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
PYEOF

# 3. Run verification script
python3 /tmp/verify_rule.py

# 4. Prepare result for export
cp /tmp/rule_verification.json /tmp/task_result.json 2>/dev/null || echo "{}" > /tmp/task_result.json

# Add file ownership fix
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json