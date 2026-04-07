#!/bin/bash
echo "=== Exporting validate_log_decoding results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/logtest_report.json"

# 1. Check if output file exists and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Generate Ground Truth
# We run the actual API calls now to get the "correct" answers from the current environment
echo "Generating ground truth data..."

# Python script to fetch ground truth and package everything
python3 << 'PYEOF'
import json
import subprocess
import sys
import os
import time

# Configuration
api_user = "wazuh-wui"
api_pass = "MyS3cr37P450r.*-"
api_url = "https://localhost:55000"

def get_token():
    cmd = [
        "curl", "-sk", "-u", f"{api_user}:{api_pass}",
        "-X", "POST", f"{api_url}/security/user/authenticate?raw=true"
    ]
    try:
        token = subprocess.check_output(cmd).decode().strip()
        return token
    except Exception as e:
        sys.stderr.write(f"Error getting token: {e}\n")
        return None

def test_log(token, log_line):
    if not token: return None
    payload = json.dumps({
        "log_format": "syslog",
        "location": "verification_gt",
        "event": log_line
    })
    cmd = [
        "curl", "-sk", "-X", "PUT", f"{api_url}/logtest",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json",
        "-d", payload
    ]
    try:
        output = subprocess.check_output(cmd).decode()
        return json.loads(output)
    except Exception as e:
        sys.stderr.write(f"Error testing log: {e}\n")
        return None

# Read samples
try:
    with open("/home/ga/log_samples.txt", "r") as f:
        samples = [line.strip() for line in f if line.strip()]
except FileNotFoundError:
    samples = []

# Get ground truth
ground_truth = []
token = get_token()

if token:
    for sample in samples:
        res = test_log(token, sample)
        if res and 'data' in res and 'output' in res['data']:
            output = res['data']['output']
            ground_truth.append({
                "sample": sample,
                "decoder": output.get('decoder', {}).get('name'),
                "rule_id": output.get('rule', {}).get('id'),
                "rule_level": output.get('rule', {}).get('level'),
                "rule_desc": output.get('rule', {}).get('description')
            })
        else:
            ground_truth.append({"sample": sample, "error": "API failed"})
else:
    sys.stderr.write("Failed to get API token for ground truth generation\n")

# Read Agent's Report safely
agent_report = None
report_path = "/home/ga/logtest_report.json"
if os.path.exists(report_path):
    try:
        with open(report_path, "r") as f:
            agent_report = json.load(f)
    except Exception as e:
        agent_report = {"error": str(e), "content_preview": "Could not parse JSON"}

# Construct Final Result JSON
result_data = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "file_exists": os.environ.get("FILE_EXISTS") == "true",
    "file_created_during_task": os.environ.get("FILE_CREATED_DURING_TASK") == "true",
    "file_size": int(os.environ.get("FILE_SIZE", 0)),
    "agent_report": agent_report,
    "ground_truth": ground_truth
}

# Write to temp file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result_data, f, indent=2)

PYEOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure result permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="