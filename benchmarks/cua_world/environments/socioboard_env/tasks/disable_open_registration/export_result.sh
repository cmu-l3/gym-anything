#!/bin/bash
set -e
echo "=== Exporting disable_open_registration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# We use a Python script to gather HTTP responses and Git diffs securely, 
# encoding them into JSON without quoting issues.
python3 -c '
import json
import subprocess
import os

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.STDOUT).strip()
    except subprocess.CalledProcessError as e:
        return e.output.strip()
    except Exception as e:
        return str(e)

# 1. Check HTTP Statuses
login_body = run_cmd("curl -s -L http://localhost/login")
login_status = run_cmd("curl -s -L -o /dev/null -w \"%{http_code}\" http://localhost/login")
register_status = run_cmd("curl -s -L -o /dev/null -w \"%{http_code}\" http://localhost/register")

# 2. Check Git Diffs against our baseline tag
run_cmd("cd /opt/socioboard/socioboard-web-php && git config --global --add safe.directory \"*\"")
mod_files_raw = run_cmd("cd /opt/socioboard/socioboard-web-php && git diff --name-only task_start_state")
mod_files = mod_files_raw.split("\n") if mod_files_raw else []

# Capture the exact diff for routes/web.php if modified
route_diff = run_cmd("cd /opt/socioboard/socioboard-web-php && git diff task_start_state routes/web.php")

data = {
    "login_body": login_body,
    "login_status": login_status,
    "register_status": register_status,
    "modified_files": mod_files,
    "route_diff": route_diff
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f)
'

# Set permissions so the verifier can read the result
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. Result saved to /tmp/task_result.json."