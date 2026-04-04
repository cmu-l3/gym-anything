#!/bin/bash
set -e
echo "=== Setting up reset_locked_user_password task ==="

source /workspace/scripts/task_utils.sh

# Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
wait_for_artifactory 120

# Record task start time
date +%s > /tmp/task_start_time.txt

# Python script to setup data using Internal UI API
# (Bypasses OSS REST API restrictions by mimicking the Web UI)
cat > /tmp/setup_data.py << 'EOF'
import requests
import json
import sys
import time

BASE_URL = "http://localhost:8082/artifactory"
UI_BASE_URL = "http://localhost:8082/ui"
ADMIN_USER = "admin"
ADMIN_PASS = "password"

session = requests.Session()

def login():
    print("Logging in...")
    headers = {"Content-Type": "application/json"}
    data = {"user": ADMIN_USER, "password": ADMIN_PASS, "type": "login"}
    resp = session.post(f"{UI_BASE_URL}/auth/login", json=data, headers=headers)
    if resp.status_code == 200:
        print("Login successful")
        return True
    print(f"Login failed: {resp.status_code} {resp.text}")
    return False

def enable_account_locking():
    print("Enabling account locking...")
    # Get current security config
    resp = session.get(f"{UI_BASE_URL}/admin/configuration/security")
    if resp.status_code != 200:
        print(f"Failed to get security config: {resp.status_code}")
        return False
    
    config = resp.json()
    # Enable locking, max attempts 3
    config['accountLocking'] = {
        'enabled': True,
        'maxFailedLoginAttempts': 3
    }
    
    # Save config
    resp = session.post(f"{UI_BASE_URL}/admin/configuration/security", json=config)
    if resp.status_code == 200:
        print("Account locking enabled.")
        return True
    print(f"Failed to enable account locking: {resp.status_code}")
    return False

def create_group(group_name):
    print(f"Creating group {group_name}...")
    # Check if exists first
    resp = session.get(f"{UI_BASE_URL}/admin/security/groups/{group_name}")
    if resp.status_code == 200:
        print("Group already exists.")
        return True

    data = {
        "name": group_name,
        "description": "Backend Developers",
        "autoJoin": False,
        "adminPrivileges": False
    }
    resp = session.post(f"{UI_BASE_URL}/admin/security/groups", json=data)
    if resp.status_code == 200:
        print(f"Group {group_name} created.")
        return True
    print(f"Failed to create group: {resp.status_code} {resp.text}")
    return False

def create_user(username, password, groups):
    print(f"Creating user {username}...")
    # Check if exists
    resp = session.get(f"{UI_BASE_URL}/admin/security/users/{username}")
    if resp.status_code == 200:
        # Delete if exists to ensure clean state (locked state reset)
        print("User exists, deleting to reset...")
        session.delete(f"{UI_BASE_URL}/admin/security/users/{username}")
        time.sleep(1)

    data = {
        "name": username,
        "email": f"{username}@example.com",
        "password": password,
        "admin": False,
        "profileUpdatable": True,
        "internalPasswordDisabled": False,
        "groups": groups
    }
    resp = session.post(f"{UI_BASE_URL}/admin/security/users", json=data)
    if resp.status_code == 200:
        print(f"User {username} created.")
        return True
    print(f"Failed to create user: {resp.status_code} {resp.text}")
    return False

def lock_user(username):
    print(f"Intentionally locking user {username}...")
    # Perform failed logins using basic auth against the API
    url = f"{BASE_URL}/api/system/ping"
    for i in range(6):
        try:
            requests.get(url, auth=(username, "WRONG_PASSWORD_123"))
        except:
            pass
    print("Failed login attempts performed.")

if __name__ == "__main__":
    if not login():
        sys.exit(1)
    
    if not enable_account_locking():
        sys.exit(1)
        
    if not create_group("backend-devs"):
        sys.exit(1)
        
    if not create_user("jmonroe", "OriginalPass123!", ["backend-devs"]):
        sys.exit(1)
        
    lock_user("jmonroe")
    print("Setup complete.")
EOF

# Run the setup script
echo "Running data setup..."
python3 /tmp/setup_data.py

# Verify user is actually locked
echo "Verifying lock state..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u jmonroe:OriginalPass123! http://localhost:8082/artifactory/api/system/ping)
if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "User jmonroe is successfully locked/unauthorized (HTTP $HTTP_CODE)."
else
    echo "WARNING: User jmonroe might not be locked (HTTP $HTTP_CODE). Continuing anyway."
fi

# Launch Firefox and navigate to login
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/login"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="