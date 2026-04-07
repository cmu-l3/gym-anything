#!/bin/bash
set -e
echo "=== Setting up Reschedule Delayed Phase task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 1. Wait for Redmine
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# 2. Get Admin API Key
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ] || [ "$API_KEY" == "null" ]; then
    echo "ERROR: Could not retrieve Admin API Key from seed result"
    exit 1
fi

# 3. Create Specific Project and Issues via Python script
# We do this to ensure specific dates and structure exist
echo "Seeding 'Coastal Wind Farm' project data..."

cat > /tmp/seed_wind_farm.py <<EOF
import requests
import json
import sys

BASE_URL = "http://localhost:3000"
API_KEY = "$API_KEY"
HEADERS = {'X-Redmine-API-Key': API_KEY, 'Content-Type': 'application/json'}

def create_project():
    # Check if exists first
    r = requests.get(f"{BASE_URL}/projects/coastal-wind-farm.json", headers=HEADERS)
    if r.status_code == 200:
        print("Project already exists")
        return r.json()['project']['id']

    payload = {
        "project": {
            "name": "Coastal Wind Farm",
            "identifier": "coastal-wind-farm",
            "description": "Offshore wind farm installation phase 1.",
            "is_public": True
        }
    }
    r = requests.post(f"{BASE_URL}/projects.json", headers=HEADERS, json=payload)
    if r.status_code == 201:
        print("Project created")
        return r.json()['project']['id']
    else:
        print(f"Failed to create project: {r.text}")
        sys.exit(1)

def create_issue(project_id, subject, start, due, description=""):
    payload = {
        "issue": {
            "project_id": project_id,
            "subject": subject,
            "start_date": start,
            "due_date": due,
            "priority_id": 4, # Urgent/High usually
            "description": description
        }
    }
    r = requests.post(f"{BASE_URL}/issues.json", headers=HEADERS, json=payload)
    if r.status_code == 201:
        print(f"Issue '{subject}' created")
    else:
        print(f"Failed to create issue '{subject}': {r.text}")

def main():
    pid = create_project()
    
    # Issue 1: Blade Delivery
    create_issue(pid, "Blade Delivery Logistics", "2026-09-01", "2026-09-05", 
                 "Coordination of turbine blade transport from port to site.")
                 
    # Issue 2: Tower Assembly (dependent on delivery in real life, but we just set dates)
    create_issue(pid, "Tower Section Assembly", "2026-09-07", "2026-09-11", 
                 "Vertical assembly of tower sections T1-T3.")
                 
    # Issue 3: Nacelle Lift
    create_issue(pid, "Nacelle and Rotor Lift", "2026-09-14", "2026-09-18", 
                 "Heavy lift operation for nacelle and rotor hub.")

if __name__ == "__main__":
    main()
EOF

python3 /tmp/seed_wind_farm.py

# 4. Prepare Firefox
TARGET_URL="$REDMINE_BASE_URL/projects/coastal-wind-farm"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine"
  exit 1
fi

focus_firefox || true
sleep 3

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured"

echo "=== Task setup complete ==="