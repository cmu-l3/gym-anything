#!/bin/bash
set -e
echo "=== Setting up Assign User Role Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Bahmni/OpenMRS is ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni not ready"
    exit 1
fi

# 3. Setup Target User 'jwilson'
# We need to ensure the user exists, has a known UUID, and DOES NOT have the target role yet.

TARGET_USER="jwilson"
TARGET_ROLE="System Developer"
BASELINE_ROLE="Provider" # User starts with this

echo "Configuring user '$TARGET_USER'..."

# Helper to execute python for complex API interactions
# (Using python ensures we handle JSON/Auth correctly without fragile bash parsing)
cat > /tmp/setup_user.py << 'EOF'
import requests
import json
import sys
import warnings

warnings.filterwarnings("ignore")

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")

def create_or_reset_user():
    # 1. Check if user exists
    resp = requests.get(f"{BASE_URL}/user?q=jwilson&v=full", auth=AUTH, verify=False)
    results = resp.json().get("results", [])
    
    user_uuid = None
    person_uuid = None
    
    # Filter for exact username match
    existing_user = next((u for u in results if u["username"] == "jwilson"), None)

    if existing_user:
        user_uuid = existing_user["uuid"]
        person_uuid = existing_user["person"]["uuid"]
        print(f"User exists: {user_uuid}")
        
        # 2. Reset roles (Remove 'System Developer' if present, ensure 'Provider')
        # We perform a POST with the exact roles list we want.
        # OpenMRS often merges roles on POST, but passing the list usually updates it.
        # Actually, simpler to retire and recreate if we want a perfectly clean state, 
        # but reusing keeps the person record. Let's try to set roles.
        
        # Note: OpenMRS REST API behavior on roles can be additive. 
        # To be safe, we check if target role exists and if so, fail or warn?
        # Better: We just verify the start state doesn't have it.
        
        current_roles = [r["display"] for r in existing_user.get("roles", [])]
        if "System Developer" in current_roles:
            print("Target role already present. Attempting to remove...")
            # Ideally we'd remove it, but OpenMRS API delete-role is tricky.
            # Strategy: Retire the user account and create a new one for a new person?
            # Or just accept we might need to purge. 
            # For this task, let's purge the user to be safe.
            requests.delete(f"{BASE_URL}/user/{user_uuid}?purge=true", auth=AUTH, verify=False)
            user_uuid = None # Signal to recreate
        else:
            print("User state clean (target role absent).")

    if not user_uuid:
        # Create Person first if needed (or reuse existing person if we just deleted the user)
        # To avoid person duplication, check person search
        if not person_uuid:
            resp = requests.get(f"{BASE_URL}/person?q=James+Wilson&v=default", auth=AUTH, verify=False)
            p_results = resp.json().get("results", [])
            if p_results:
                person_uuid = p_results[0]["uuid"]
            else:
                # Create Person
                p_payload = {
                    "names": [{"givenName": "James", "familyName": "Wilson"}],
                    "gender": "M",
                    "age": 40
                }
                resp = requests.post(f"{BASE_URL}/person", json=p_payload, auth=AUTH, verify=False)
                if resp.status_code not in [200, 201]:
                    print(f"Error creating person: {resp.text}")
                    sys.exit(1)
                person_uuid = resp.json()["uuid"]

        # Create User
        u_payload = {
            "username": "jwilson",
            "password": "Password123",
            "person": person_uuid,
            "roles": [{"role": "Provider"}]
        }
        resp = requests.post(f"{BASE_URL}/user", json=u_payload, auth=AUTH, verify=False)
        if resp.status_code not in [200, 201]:
            print(f"Error creating user: {resp.text}")
            sys.exit(1)
        user_uuid = resp.json()["uuid"]
        print(f"Created new user: {user_uuid}")

    # Output UUID for setup script to capture
    with open("/tmp/target_user_uuid.txt", "w") as f:
        f.write(user_uuid)

if __name__ == "__main__":
    create_or_reset_user()
EOF

python3 /tmp/setup_user.py

# 4. Launch Browser
# We want to start at the Admin page to save the agent some navigation time, 
# or start at Home and let them navigate. The description says "Navigate to...".
# Starting at login page or home is best.
start_browser "${BAHMNI_BASE_URL}/openmrs/admin"

# 5. Capture Initial State
sleep 5
take_screenshot /tmp/task_initial.png

# Verify UUID was saved
if [ ! -f /tmp/target_user_uuid.txt ]; then
    echo "ERROR: Failed to prepare target user."
    exit 1
fi

echo "Target User UUID: $(cat /tmp/target_user_uuid.txt)"
echo "=== Setup complete ==="