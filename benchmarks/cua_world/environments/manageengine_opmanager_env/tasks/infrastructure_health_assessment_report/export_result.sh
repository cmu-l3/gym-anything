#!/bin/bash
# export_result.sh — Infrastructure Health Assessment Report
# Collects the report file, OpManager device ground truth via API, and system metrics.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/health_assessment_result.json"
TMP_DEVICES_API="/tmp/_health_devices_api.json"

# ------------------------------------------------------------
# 1. Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST \
        "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))
except Exception:
    pass
" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# 2. Fetch device list via API to get OpManager ground truth
# ------------------------------------------------------------
echo "[export] Fetching device list via API..."
curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" > "$TMP_DEVICES_API" 2>/dev/null || echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 3. Assemble final result using Python
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json
import os
import subprocess
import time

result = {}
report_path = "/home/ga/Desktop/health_assessment_report.txt"
start_time_file = "/tmp/task_start_time.txt"

# 1. Check report file
if os.path.exists(report_path):
    result['report_exists'] = True
    result['report_size_bytes'] = os.path.getsize(report_path)
    result['report_mtime'] = os.path.getmtime(report_path)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='replace') as f:
            result['report_content'] = f.read()
    except Exception as e:
        result['report_content'] = f"Error reading file: {e}"
else:
    result['report_exists'] = False
    result['report_size_bytes'] = 0
    result['report_mtime'] = 0
    result['report_content'] = ""

# 2. Get task start time
try:
    with open(start_time_file, 'r') as f:
        result['task_start_time'] = float(f.read().strip())
except:
    result['task_start_time'] = 0.0

# 3. Read API device list to find 127.0.0.1
target_device = {}
try:
    with open("/tmp/_health_devices_api.json", 'r') as f:
        api_data = json.load(f)
        
        # Extract devices list
        devices = []
        for key in ["data", "devices", "deviceList", "result"]:
            if isinstance(api_data.get(key), list):
                devices = api_data[key]
                break
            elif isinstance(api_data.get(key), dict):
                inner = api_data[key]
                for inner_key in ["data", "devices", "deviceList"]:
                    if isinstance(inner.get(inner_key), list):
                        devices = inner[inner_key]
                        break
        
        for d in devices:
            ip = d.get('ipAddress', d.get('ip', d.get('deviceIP', '')))
            if ip == "127.0.0.1":
                target_device = {
                    "name": d.get('displayName', d.get('name', '')),
                    "status": d.get('status', d.get('deviceStatus', 'unknown')),
                    "type": d.get('type', d.get('category', 'unknown'))
                }
                break
except Exception as e:
    target_device = {"error": str(e)}

result['api_ground_truth'] = target_device

# 4. Get live OS metrics (which SNMP/OpManager reads) as absolute ground truth
try:
    # CPU: Use top
    top_out = subprocess.check_output("top -bn2 | grep 'Cpu(s)' | tail -n1", shell=True).decode('utf-8')
    # e.g., %Cpu(s):  2.0 us,  1.0 sy,  0.0 ni, 97.0 id
    # Calculate non-idle
    import re
    idle_match = re.search(r'([0-9.]+)\s+id', top_out)
    if idle_match:
        cpu_usage = 100.0 - float(idle_match.group(1))
    else:
        cpu_usage = 5.0 # fallback
    result['os_cpu_utilization'] = round(cpu_usage, 2)
    
    # Mem: Use free
    free_out = subprocess.check_output("free -m | grep Mem", shell=True).decode('utf-8').split()
    total_mem = float(free_out[1])
    used_mem = float(free_out[2])
    result['os_mem_utilization'] = round((used_mem / total_mem) * 100.0, 2) if total_mem > 0 else 0.0
except Exception as e:
    result['os_metrics_error'] = str(e)
    result['os_cpu_utilization'] = 10.0 # generous fallbacks
    result['os_mem_utilization'] = 50.0

# Write to temp and copy to final
import shutil
tmp_out = "/tmp/health_assessment_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

shutil.move(tmp_out, "/tmp/health_assessment_result.json")
os.chmod("/tmp/health_assessment_result.json", 0o666)
PYEOF

echo "[export] Result written to $RESULT_FILE"