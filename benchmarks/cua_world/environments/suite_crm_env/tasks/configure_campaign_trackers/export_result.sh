#!/bin/bash
echo "=== Exporting configure_campaign_trackers results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for trajectory and visual evaluation
take_screenshot /tmp/configure_campaign_trackers_final.png

# Retrieve Campaign data
CAMPAIGN_DATA=$(suitecrm_db_query "SELECT id, name, campaign_type, status, budget, expected_revenue, created_by FROM campaigns WHERE name='Industrial Sensor Launch 2026' AND deleted=0 LIMIT 1")

C_ID=""
TRACKERS_DATA=""

if [ -n "$CAMPAIGN_DATA" ]; then
    C_ID=$(echo "$CAMPAIGN_DATA" | awk -F'\t' '{print $1}')
    # Retrieve Tracker URLs associated with this campaign
    TRACKERS_DATA=$(suitecrm_db_query "SELECT tracker_name, tracker_url, created_by FROM campaign_trkrs WHERE campaign_id='${C_ID}' AND deleted=0")
fi

# Use Python to safely format the retrieved data into a valid JSON object
python3 <<EOF > /tmp/temp_result.json
import json
import os

campaign_data_raw = """${CAMPAIGN_DATA:-}"""
trackers_raw = """${TRACKERS_DATA:-}"""

campaign_found = False
campaign_dict = {}

if campaign_data_raw.strip():
    campaign_found = True
    parts = campaign_data_raw.strip().split('\t')
    if len(parts) >= 7:
        campaign_dict = {
            "id": parts[0],
            "name": parts[1],
            "type": parts[2],
            "status": parts[3],
            "budget": parts[4],
            "expected_revenue": parts[5],
            "created_by": parts[6]
        }

trackers = []
if trackers_raw.strip():
    for line in trackers_raw.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 3:
            trackers.append({
                "name": parts[0],
                "url": parts[1],
                "created_by": parts[2]
            })

start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    try:
        start_time = int(open("/tmp/task_start_time.txt").read().strip())
    except:
        pass

data = {
    "campaign_found": campaign_found,
    "campaign": campaign_dict,
    "trackers": trackers,
    "task_start_time": start_time,
    "export_timestamp": os.popen("date +%s").read().strip()
}

with open("/tmp/temp_result.json", "w") as f:
    json.dump(data, f, indent=2)
EOF

safe_write_result "/tmp/configure_campaign_trackers_result.json" "$(cat /tmp/temp_result.json)"
rm -f /tmp/temp_result.json

echo "Result safely exported to /tmp/configure_campaign_trackers_result.json"
cat /tmp/configure_campaign_trackers_result.json
echo "=== configure_campaign_trackers export complete ==="