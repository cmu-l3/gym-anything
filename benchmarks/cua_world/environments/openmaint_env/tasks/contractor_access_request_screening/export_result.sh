#!/bin/bash
echo "=== Exporting Contractor Access Request results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate", file=sys.stderr)
    sys.exit(0)

# Load class info
try:
    with open("/tmp/wo_class_info.json", "r") as f:
        class_info = json.load(f)
    wo_type = class_info["type"]
    wo_cls = class_info["class"]
except:
    # Fallback discovery
    wo_type, wo_cls = find_maintenance_class(token)

if not wo_cls:
    result = {"error": "Could not determine Work Order class"}
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(0)

# Get all Work Orders
# In a real scenario with many records, we'd filter by creation date or similar.
# Here we'll fetch recent ones and filter in python if needed, or rely on the agent creating them at the end.
records = get_records(wo_type, wo_cls, token, limit=100)

exported_wos = []
for r in records:
    # Extract fields relevant to verification
    wo_data = {
        "id": r.get("_id"),
        "code": r.get("Code", ""),
        "description": r.get("Description", ""),
        "notes": r.get("Notes", ""),
        "create_date": r.get("BeginDate", "") or r.get("_begin_date", ""), # approximate creation time check
    }
    
    # Resolve Building
    # Building might be a reference object or just an ID
    b_ref = r.get("Building") or r.get("Location")
    if isinstance(b_ref, dict):
        wo_data["building_desc"] = b_ref.get("description", "") or b_ref.get("code", "")
    elif b_ref:
        wo_data["building_desc"] = str(b_ref)
    else:
        wo_data["building_desc"] = ""

    exported_wos.append(wo_data)

# Load baseline count
try:
    with open("/tmp/initial_wo_count.txt", "r") as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

result = {
    "initial_count": initial_count,
    "final_count": len(records),
    "work_orders": exported_wos,
    "wo_class": wo_cls
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="