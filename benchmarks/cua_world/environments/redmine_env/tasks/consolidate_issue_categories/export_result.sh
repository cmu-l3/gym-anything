#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting consolidate_issue_categories result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to gather verification data
# We run this inside the container to access the API and ground truth file
cat > /tmp/gather_results.py << 'EOF'
import json
import sys
import requests
import os

# Load ground truth
try:
    with open("/home/ga/ground_truth.json", "r") as f:
        truth = json.load(f)
except FileNotFoundError:
    print(json.dumps({"error": "Ground truth file not found"}))
    sys.exit(0)

# Load API Key
try:
    with open("/home/ga/redmine_seed_result.json", "r") as f:
        seed = json.load(f)
        api_key = seed.get("admin_api_key")
except:
    print(json.dumps({"error": "API key not found"}))
    sys.exit(0)

base_url = "http://localhost:3000"
headers = {"X-Redmine-API-Key": api_key}
project_id = truth["project_id"]

result = {
    "error": None,
    "final_categories": [],
    "issue_states": [],
    "ground_truth": truth
}

# 1. Fetch current categories
try:
    r = requests.get(f"{base_url}/projects/{project_id}/issue_categories.json", headers=headers)
    if r.status_code == 200:
        result["final_categories"] = r.json().get("issue_categories", [])
    else:
        result["error"] = f"Failed to fetch categories: {r.status_code}"
except Exception as e:
    result["error"] = str(e)

# 2. Fetch state of tracked issues
for item in truth["issues"]:
    iid = item["id"]
    try:
        r_issue = requests.get(f"{base_url}/issues/{iid}.json", headers=headers)
        if r_issue.status_code == 200:
            issue_data = r_issue.json()["issue"]
            result["issue_states"].append({
                "id": iid,
                "exists": True,
                "category_name": issue_data.get("category", {}).get("name"),
                "category_id": issue_data.get("category", {}).get("id")
            })
        else:
            result["issue_states"].append({
                "id": iid,
                "exists": False
            })
    except Exception as e:
         result["issue_states"].append({"id": iid, "error": str(e)})

print(json.dumps(result))
EOF

# Run result gathering and save to /tmp/task_result.json
python3 /tmp/gather_results.py > /tmp/task_result.json

# Ensure result file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result export complete."
cat /tmp/task_result.json