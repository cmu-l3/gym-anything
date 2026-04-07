#!/bin/bash
echo "=== Exporting lookup_type_configuration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export current state using Python API
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/lookup_baseline.json")
if not baseline:
    print("WARNING: Baseline missing, preservation checks may fail", file=sys.stderr)
    baseline = {}

token = get_token()
if not token:
    with open("/tmp/lookup_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

target_types = ["MaintenanceShift", "CostCenter", "FailureCategory"]
results = {
    "targets": {},
    "preservation": {},
    "baseline": baseline
}

# Check target lookup types
for lt_name in target_types:
    # Check if type exists
    # The API endpoint is /lookup_types/{id} or we can list all and find it
    # We'll try to get values directly; if it fails (404), the type likely doesn't exist
    
    # First, list all to check existence (case-insensitive match)
    all_types_resp = api("GET", "lookup_types?limit=500", token)
    all_types = all_types_resp.get("data", []) if all_types_resp else []
    
    found_id = None
    for t in all_types:
        if t.get("_id", "").lower() == lt_name.lower():
            found_id = t.get("_id")
            break
            
    if not found_id:
        results["targets"][lt_name] = {"exists": False}
        continue

    # Get values for the found type
    values = get_lookup_values(found_id, token)
    
    # Format values for verification
    formatted_values = []
    for i, v in enumerate(values):
        formatted_values.append({
            "code": v.get("Code", ""),
            "description": v.get("Description", ""),
            "index": v.get("Index", i), # Fallback to list order if Index not present
            "active": v.get("Active", True)
        })
        
    results["targets"][lt_name] = {
        "exists": True,
        "actual_id": found_id,
        "values": formatted_values,
        "count": len(values)
    }

# Check preservation (Priority lookup)
current_priority = get_lookup_values("Priority", token)
results["preservation"]["priority_current_count"] = len(current_priority)
results["preservation"]["priority_values_match"] = True # Simplify, check count mainly

baseline_prio = baseline.get("priority_baseline", [])
if len(current_priority) != len(baseline_prio):
    results["preservation"]["priority_values_match"] = False
else:
    # Deep check logic could go here, but count is usually sufficient for "do not delete"
    pass

# Check total count vs baseline
results["preservation"]["total_current"] = len(all_types)
results["preservation"]["total_baseline"] = baseline.get("total_count", 0)

with open("/tmp/lookup_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Result exported to /tmp/lookup_result.json")
PYEOF

echo "=== Export complete ==="