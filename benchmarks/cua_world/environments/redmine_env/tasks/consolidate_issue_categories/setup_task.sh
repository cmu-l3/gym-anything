#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up consolidate_issue_categories task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Redmine to be reachable
wait_for_http "$REDMINE_BASE_URL/login" 120

# Create the python data setup script
cat > /tmp/setup_data.py << 'EOF'
import json
import os
import sys
import requests
import random

# Read Admin API Key from seed result
def get_admin_key():
    try:
        with open("/home/ga/redmine_seed_result.json", "r") as f:
            data = json.load(f)
            return data.get("admin_api_key")
    except Exception as e:
        print(f"Error reading seed result: {e}")
        return None

API_KEY = get_admin_key()
BASE_URL = "http://localhost:3000"
HEADERS = {"X-Redmine-API-Key": API_KEY, "Content-Type": "application/json"}

if not API_KEY:
    sys.exit("No API key found")

def create_project():
    # Check if exists first
    projs = requests.get(f"{BASE_URL}/projects.json", headers=HEADERS).json()
    for p in projs.get("projects", []):
        if p["identifier"] == "office-renovation":
            return p["id"]
            
    payload = {
        "project": {
            "name": "Office Renovation",
            "identifier": "office-renovation",
            "description": "Renovation of the downtown HQ. Tracks all facility updates.",
            "is_public": False
        }
    }
    r = requests.post(f"{BASE_URL}/projects.json", headers=HEADERS, json=payload)
    if r.status_code == 201:
        return r.json()["project"]["id"]
    sys.exit(f"Failed to create project: {r.text}")

def create_category(project_id, name):
    # Check existence
    cats = requests.get(f"{BASE_URL}/projects/{project_id}/issue_categories.json", headers=HEADERS).json()
    for c in cats.get("issue_categories", []):
        if c["name"] == name:
            return c["id"]

    payload = {"issue_category": {"name": name}}
    r = requests.post(f"{BASE_URL}/projects/{project_id}/issue_categories.json", headers=HEADERS, json=payload)
    if r.status_code == 201:
        return r.json()["issue_category"]["id"]
    return None

def create_issue(project_id, category_id, subject):
    payload = {
        "issue": {
            "project_id": project_id,
            "category_id": category_id,
            "subject": subject,
            "priority_id": 2, # Normal
            "tracker_id": 1   # Bug
        }
    }
    r = requests.post(f"{BASE_URL}/issues.json", headers=HEADERS, json=payload)
    if r.status_code == 201:
        return r.json()["issue"]["id"]
    return None

# Execute Setup
print("Creating project...")
pid = create_project()

print("Creating categories...")
cat_plumbing = create_category(pid, "Plumbing")
cat_electrical = create_category(pid, "Electrical")
cat_mep = create_category(pid, "MEP")
create_category(pid, "General") # Decoy

# Create Issues
issues = []
plumbing_tasks = [
    "Fix leak in 2F Breakroom sink", 
    "Replace flush valve in West Wing", 
    "Inspect water heater pilot light"
]
electrical_tasks = [
    "Install quad outlets in Server Room B", 
    "Replace flickering ballast in hallway"
]

print("Creating issues...")
for task in plumbing_tasks:
    iid = create_issue(pid, cat_plumbing, task)
    if iid:
        issues.append({"id": iid, "original_category": "Plumbing", "subject": task})

for task in electrical_tasks:
    iid = create_issue(pid, cat_electrical, task)
    if iid:
        issues.append({"id": iid, "original_category": "Electrical", "subject": task})

# Save ground truth for verification
ground_truth = {
    "project_id": pid,
    "categories": {
        "plumbing_id": cat_plumbing,
        "electrical_id": cat_electrical,
        "mep_id": cat_mep
    },
    "issues": issues,
    "timestamp": os.popen("date +%s").read().strip()
}

with open("/home/ga/ground_truth.json", "w") as f:
    json.dump(ground_truth, f)

print("Setup data generation complete.")
EOF

# Run the python setup script
python3 /tmp/setup_data.py

# Ensure permissions on ground truth
chown ga:ga /home/ga/ground_truth.json

# Log in and navigate to the project
TARGET_URL="$REDMINE_BASE_URL/projects/office-renovation"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine."
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task start screenshot: /tmp/task_initial.png"

echo "=== Setup complete ==="