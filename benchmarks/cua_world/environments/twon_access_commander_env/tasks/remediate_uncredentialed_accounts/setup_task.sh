#!/bin/bash
echo "=== Setting up remediate_uncredentialed_accounts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander to be reachable
wait_for_ac_demo

# Inject the uncredentialed users using Python (more robust for nested JSON)
cat > /tmp/inject_uncredentialed.py << 'EOF'
import requests, urllib3, json

urllib3.disable_warnings()
s = requests.Session()
s.verify = False
URL = "https://localhost:9443"

# Login
resp = s.put(f"{URL}/api/v3/auth", json={"login": "admin", "password": "2n"})
if resp.status_code not in (200, 201):
    print("Failed to authenticate")
    exit(1)

# Delete targets if they exist from a previous run
users = s.get(f"{URL}/api/v3/users").json()
for u in users:
    fname = u.get('firstName', '')
    lname = u.get('lastName', '')
    if fname in ['Julian', 'Chloe'] and ('Bautista' in lname or 'Arnaud' in lname):
        s.delete(f"{URL}/api/v3/users/{u['id']}")

# Get Employees group id
groups = s.get(f"{URL}/api/v3/groups").json()
emp_group_id = next((g.get('id') for g in groups if g.get('name') == 'Employees'), None)

# Inject the two users without credentials
new_users = [
    {"firstName": "Julian", "lastName": "Bautista", "email": "j.bautista@buildingtech.com", "company": "BuildingTech Solutions"},
    {"firstName": "Chloe", "lastName": "Arnaud", "email": "c.arnaud@buildingtech.com", "company": "BuildingTech Solutions"}
]

for u in new_users:
    r = s.post(f"{URL}/api/v3/users", json=u)
    if r.status_code in (200, 201) and emp_group_id:
        uid = r.json().get('id')
        s.put(f"{URL}/api/v3/users/{uid}/groups/{emp_group_id}")
        print(f"Created uncredentialed user: {u['firstName']} {u['lastName']}")
EOF

python3 /tmp/inject_uncredentialed.py

# Launch Firefox and navigate to Users list
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="