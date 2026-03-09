#!/bin/bash
echo "=== Setting up Configure Business Rule task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for SDP to be ready
ensure_sdp_running

# 2. Write the login helper script
write_python_login_script

# 3. Create Prerequisites (Group, Category, Subcategory) via Python
# We use the internal API/HTTP interface to populate this data so the agent has something to select.
cat > /tmp/setup_prereqs.py << 'PYEOF'
import sys
import json
import requests
# Import the login helper created by task_utils.sh
sys.path.append('/tmp')
from sdp_login import login, BASE

def setup_data():
    s = requests.Session()
    if not login(s):
        print("Failed to login")
        sys.exit(1)
    
    print("Logged in. Creating prerequisites...")
    
    # Headers for AJAX requests
    headers = {'Content-Type': 'application/x-www-form-urlencoded'}
    
    # 1. Create Technician Group: "Network Support"
    # Note: Endpoints vary by SDP version, using standard form submissions often works best
    # or using the API if Technician Key is available. 
    # Since we have a session, we can try to use the internal functional creation URLs or API.
    # For stability in this environment, we will use the API v3 if possible, or v1.
    
    # Generate API key first
    try:
        # Try to generate API key
        r = s.get(f"{BASE}/api/v3/app_resources/technician_key", verify=False)
        # If that fails, we might need to rely on DB or simple HTTP posts.
    except:
        pass

    # Fallback: Use direct DB inserts for robust setup if API is tricky without a key
    # (SDP schema is complex, but basic lookup tables are often accessible)
    # Actually, simplest is to use the UI endpoints or check if they exist.
    pass

if __name__ == "__main__":
    setup_data()
PYEOF

# Execute Python setup (logging attempt)
# Note: For this task, we will use DB inserts for speed and reliability 
# if the Python API interaction is complex.
# However, `sdp_db_exec` is available. 

# Create Technician Group "Network Support" directly in DB if not exists
echo "Creating Technician Group..."
sdp_db_exec "INSERT INTO queuemechanism (queue_id, queuename, description) VALUES ((SELECT COALESCE(MAX(queue_id),0)+1 FROM queuemechanism), 'Network Support', 'Handles network issues') ON CONFLICT DO NOTHING;"

# Create Category "Network"
echo "Creating Category..."
sdp_db_exec "INSERT INTO categorydefinition (categoryid, categoryname) VALUES ((SELECT COALESCE(MAX(categoryid),0)+1 FROM categorydefinition), 'Network') ON CONFLICT DO NOTHING;"
CAT_ID=$(sdp_db_exec "SELECT categoryid FROM categorydefinition WHERE categoryname='Network';")

# Create Subcategory "Connectivity"
if [ -n "$CAT_ID" ]; then
    echo "Creating Subcategory..."
    sdp_db_exec "INSERT INTO subcategorydefinition (subcategoryid, categoryid, subcategoryname) VALUES ((SELECT COALESCE(MAX(subcategoryid),0)+1 FROM subcategorydefinition), $CAT_ID, 'Connectivity') ON CONFLICT DO NOTHING;"
fi

# 4. Open Firefox to Admin page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/app/admin/home"

# 5. Record start time
date +%s > /tmp/task_start_time.txt
sdp_db_exec "SELECT count(*) FROM businessrule" > /tmp/initial_rule_count.txt

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="