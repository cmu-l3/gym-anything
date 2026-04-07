#!/bin/bash
echo "=== Exporting False Alarm Verification Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import json, os, subprocess, time

def api_get(endpoint):
    token = open("/tmp/nx_api_token").read().strip() if os.path.exists("/tmp/nx_api_token") else ""
    if not token:
        return None
    try:
        r = subprocess.run(
            ["curl", "-sk", "-H", f"Authorization: Bearer {token}",
             f"https://localhost:7001{endpoint}"],
            capture_output=True, text=True, timeout=10
        )
        return json.loads(r.stdout)
    except:
        return None

result = {
    "task_start": int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0,
    "task_end": int(time.time()),
    "ground_truth": {},
    "bookmarks": [],
    "devices": [],
    "report_content": "",
    "report_exists": False,
    "screenshot_path": "/tmp/task_final.png"
}

gt_path = "/var/lib/nx_witness_ground_truth/ground_truth.json"
if os.path.exists(gt_path):
    try:
        result["ground_truth"] = json.load(open(gt_path))
    except:
        pass

bookmarks = api_get("/rest/v1/bookmarks")
if bookmarks is not None:
    result["bookmarks"] = bookmarks
devices = api_get("/rest/v1/devices")
if devices is not None:
    result["devices"] = devices

report_path = "/home/ga/alarm_review.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_content"] = open(report_path).read()

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
os.chmod("/tmp/task_result.json", 0o666)
print("Result exported to /tmp/task_result.json")
PYEOF
