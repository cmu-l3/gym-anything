#!/bin/bash
echo "=== Exporting SSH Dashboard Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query OpenSearch Dashboards Saved Objects API
# We need to export the dashboard and visualizations to verify their configuration.
# API credentials (default for Wazuh all-in-one)
KIBANA_USER="wazuh-wui"
KIBANA_PASS="MyS3cr37P450r.*-"
API_BASE="https://localhost/api/saved_objects"

echo "Querying Saved Objects API..."

# Create a Python script to fetch and format the JSON safely
# (Bash JSON parsing is fragile, doing it in Python inside the export is safer)
cat > /tmp/fetch_objects.py << PYEOF
import requests
import json
import sys

# Configuration
URL = "${API_BASE}/_find"
AUTH = ("${KIBANA_USER}", "${KIBANA_PASS}")
VERIFY = False

results = {
    "dashboards": [],
    "visualizations": [],
    "api_accessible": False
}

try:
    # Fetch Dashboards
    r_dash = requests.get(f"{URL}?type=dashboard&per_page=50", auth=AUTH, verify=VERIFY)
    if r_dash.status_code == 200:
        results["dashboards"] = r_dash.json().get("saved_objects", [])
        results["api_accessible"] = True
    
    # Fetch Visualizations
    r_vis = requests.get(f"{URL}?type=visualization&per_page=50", auth=AUTH, verify=VERIFY)
    if r_vis.status_code == 200:
        results["visualizations"] = r_vis.json().get("saved_objects", [])

except Exception as e:
    results["error"] = str(e)

# Output structure
output = {
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "screenshot_path": "/tmp/task_final.png",
    "saved_objects": results
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export logic complete.")
PYEOF

# Execute the python script
# We use the system python3 which has requests installed (standard in this env)
python3 /tmp/fetch_objects.py || echo "Python export script failed"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="