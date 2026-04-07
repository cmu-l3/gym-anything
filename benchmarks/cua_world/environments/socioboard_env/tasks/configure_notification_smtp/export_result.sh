#!/bin/bash
echo "=== Exporting Configure Notification SMTP task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read baseline times
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_config_mtime.txt 2>/dev/null || echo "0")

# Use Python to safely gather all data and export to JSON
python3 << EOF
import json
import os
import subprocess

result = {
    "task_start": int("$TASK_START"),
    "initial_mtime": int("$INITIAL_MTIME"),
    "config_mtime": 0,
    "config_content": None,
    "config_valid_json": False,
    "report_exists": False,
    "report_content": "",
    "pm2_status": "unknown"
}

config_path = "/opt/socioboard/socioboard-api/notification/config/development.json"
report_path = "/home/ga/notification_smtp_report.txt"

# 1. Get config file stats and content
if os.path.exists(config_path):
    result["config_mtime"] = int(os.stat(config_path).st_mtime)
    try:
        with open(config_path, 'r') as f:
            content = f.read()
            # Try to parse as JSON
            try:
                result["config_content"] = json.loads(content)
                result["config_valid_json"] = True
            except json.JSONDecodeError:
                result["config_content"] = content
                result["config_valid_json"] = False
    except Exception as e:
        result["config_content"] = f"Error reading config: {str(e)}"

# 2. Get report stats and content
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, 'r') as f:
            result["report_content"] = f.read()
    except Exception as e:
        result["report_content"] = f"Error reading report: {str(e)}"

# 3. Get PM2 status for 'notification' service
try:
    # Run as ga user since the service was started as ga
    pm2_out = subprocess.check_output("su - ga -c 'pm2 jlist'", shell=True, stderr=subprocess.DEVNULL)
    pm2_data = json.loads(pm2_out)
    for process in pm2_data:
        if process.get("name") == "notification":
            result["pm2_status"] = process.get("pm2_env", {}).get("status", "unknown")
            break
except Exception as e:
    result["pm2_status"] = f"error checking pm2"

# Save result safely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="