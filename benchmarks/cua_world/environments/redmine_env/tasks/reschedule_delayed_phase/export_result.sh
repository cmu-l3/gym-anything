#!/bin/bash
echo "=== Exporting Reschedule Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
log "Final screenshot captured"

# 2. Extract Data from Redmine API
# We need to fetch the issues from the specific project and check their dates
API_KEY=$(redmine_admin_api_key)

if [ -z "$API_KEY" ]; then
    echo "Warning: API Key not found, using default extraction method might fail"
fi

# Python script to dump current state of the relevant issues
cat > /tmp/export_issues.py <<EOF
import requests
import json
import os

BASE_URL = "http://localhost:3000"
API_KEY = "$API_KEY"
HEADERS = {'X-Redmine-API-Key': API_KEY, 'Content-Type': 'application/json'}
PROJECT_ID = "coastal-wind-farm"

def main():
    output = {
        "project_exists": False,
        "issues": []
    }

    # Check project
    r = requests.get(f"{BASE_URL}/projects/{PROJECT_ID}.json", headers=HEADERS)
    if r.status_code == 200:
        output["project_exists"] = True
    else:
        print(json.dumps(output))
        return

    # Get issues
    # filtering by project_id in params
    r = requests.get(f"{BASE_URL}/issues.json?project_id={PROJECT_ID}&status_id=*", headers=HEADERS)
    if r.status_code == 200:
        issues_data = r.json().get('issues', [])
        
        # For each issue, we might want details (journals) if we need to check notes
        for issue_summary in issues_data:
            iid = issue_summary['id']
            # Get full detail for journals
            detail_r = requests.get(f"{BASE_URL}/issues/{iid}.json?include=journals", headers=HEADERS)
            if detail_r.status_code == 200:
                output["issues"].append(detail_r.json()['issue'])
            else:
                output["issues"].append(issue_summary) # Fallback

    with open("/tmp/task_result.json", "w") as f:
        json.dump(output, f, indent=2)

if __name__ == "__main__":
    main()
EOF

python3 /tmp/export_issues.py

# Check if file was created
if [ -f "/tmp/task_result.json" ]; then
    echo "Export successful:"
    cat /tmp/task_result.json
else
    echo "Export failed."
    echo "{}" > /tmp/task_result.json
fi

# 3. Record Metadata
# App running check
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then APP_RUNNING="true"; fi

# Add extra metadata to result (using jq if available, or python)
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['app_running'] = $APP_RUNNING
data['screenshot_exists'] = os.path.exists('/tmp/task_final.png')

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

echo "=== Export complete ==="