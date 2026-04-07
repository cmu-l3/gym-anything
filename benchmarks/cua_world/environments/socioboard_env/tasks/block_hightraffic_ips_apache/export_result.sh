#!/bin/bash
echo "=== Exporting task results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to safely collect all required verification data into JSON format
python3 - << 'EOF'
import json
import os
import subprocess

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "file_content": "",
    "apache_status": "inactive",
    "apache_configtest": "",
    "ground_truth": [],
    "config_matches": {}
}

task_start = 0
try:
    with open("/tmp/task_start_time.txt") as f:
        task_start = int(f.read().strip())
except:
    pass

# Read the file the agent was supposed to create
file_path = "/home/ga/blocked_ips.txt"
if os.path.exists(file_path):
    result["file_exists"] = True
    try:
        with open(file_path) as f:
            result["file_content"] = f.read()
    except:
        pass
    mtime = os.stat(file_path).st_mtime
    if mtime > task_start:
        result["file_created_during_task"] = True

# Check Apache service state
try:
    status = subprocess.check_output(["systemctl", "is-active", "apache2"], stderr=subprocess.STDOUT, text=True).strip()
    result["apache_status"] = status
except subprocess.CalledProcessError as e:
    result["apache_status"] = e.output.strip() if e.output else "failed"

# Check Apache syntax configuration
try:
    configtest = subprocess.check_output(["apache2ctl", "configtest"], stderr=subprocess.STDOUT, text=True).strip()
    result["apache_configtest"] = configtest
except subprocess.CalledProcessError as e:
    result["apache_configtest"] = e.output.strip() if e.output else "failed"

# Check if the specific targeted IPs were actually placed in the apache configuration
try:
    with open("/tmp/ground_truth.json") as f:
        gt = json.load(f)
        result["ground_truth"] = gt
        for item in gt:
            ip = item["ip"]
            try:
                grep_out = subprocess.check_output(["grep", "-r", ip, "/etc/apache2/"], text=True)
                result["config_matches"][ip] = len(grep_out.strip().splitlines())
            except subprocess.CalledProcessError:
                result["config_matches"][ip] = 0
except:
    pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="