#!/bin/bash
echo "=== Setting up emergency_comms_data_hygiene task ==="
source /workspace/scripts/task_utils.sh

# Wait for Access Commander to boot and seed data
wait_for_ac_demo

# Blank out the fields for the target users
cat << 'EOF' > /tmp/blank_users.py
import sys, json, requests
import urllib3
urllib3.disable_warnings()

AC_URL = "https://localhost:9443"
s = requests.Session()
s.verify = False

try:
    resp = s.put(f"{AC_URL}/api/v3/auth", json={"login": "admin", "password": "2n"}, timeout=10)
    if resp.status_code not in (200, 201):
        print("Login failed")
        sys.exit(1)

    users = s.get(f"{AC_URL}/api/v3/users", timeout=10).json()

    targets = {
        ("Marcus", "Webb"): ("email",),
        ("Leon", "Fischer"): ("phone",),
        ("Fatima", "Al-Rashid"): ("email", "phone"),
        ("Tomás", "Guerrero"): ("email",),
        ("Rachel", "Goldstein"): ("phone",)
    }

    for u in users:
        key = (u.get("firstName"), u.get("lastName"))
        if key in targets:
            new_data = dict(u)
            for field in targets[key]:
                new_data[field] = ""
            s.put(f"{AC_URL}/api/v3/users/{u['id']}", json=new_data, timeout=10)
            print(f"Blanked fields {targets[key]} for {key}")
except Exception as e:
    print(f"Error blanking users: {e}")
EOF

python3 /tmp/blank_users.py

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Launch Firefox pointing directly to the Users page
launch_firefox_to "https://localhost:9443/#/users" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="