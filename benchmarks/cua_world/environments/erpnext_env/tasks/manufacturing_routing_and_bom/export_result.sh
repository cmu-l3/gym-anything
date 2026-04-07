#!/bin/bash
# Export script for manufacturing_routing_and_bom task
# Queries ERPNext for Workstations, Operations, and the BOM for Advanced Wind Turbine.
# Writes results to /tmp/manufacturing_routing_and_bom_result.json

echo "=== Exporting manufacturing_routing_and_bom results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/manufacturing_routing_and_bom_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys, os

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

r = session.post(f"{ERPNEXT_URL}/api/method/login",
                 json={"usr": "Administrator", "pwd": "admin"})
if r.status_code != 200:
    print(f"ERROR: Login failed {r.status_code}", file=sys.stderr)
    sys.exit(1)

def api_get(doctype, filters=None, fields=None, limit=20):
    params = {"limit_page_length": limit}
    if filters:
        params["filters"] = json.dumps(filters)
    if fields:
        params["fields"] = json.dumps(fields)
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params)
    return resp.json().get("data", [])

def get_doc(doctype, name):
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    return resp.json().get("data", {})

# --- Query Workstations ---
workstations = {}
for ws_name in ["Assembly Station", "Testing Station"]:
    ws_records = api_get("Workstation", [["workstation_name", "=", ws_name]], fields=["name", "hour_rate"])
    if ws_records:
        workstations[ws_name] = {"exists": True, "hour_rate": float(ws_records[0].get("hour_rate", 0))}
    else:
        workstations[ws_name] = {"exists": False, "hour_rate": 0}

# --- Query Operations ---
operations = {}
for op_name in ["Mechanical Assembly", "Quality Testing"]:
    op_records = api_get("Operation", [["name", "=", op_name]], fields=["name"])
    operations[op_name] = {"exists": len(op_records) > 0}

# --- Query BOM ---
bom_list = api_get("BOM", 
                   [["item", "=", "Advanced Wind Turbine"], ["docstatus", "=", 1]], 
                   fields=["name", "operating_cost", "creation"],
                   limit=5)

bom_info = None
if bom_list:
    # Get the latest submitted BOM
    latest_bom = sorted(bom_list, key=lambda x: x.get("creation", ""), reverse=True)[0]
    doc = get_doc("BOM", latest_bom["name"])
    
    items = []
    for itm in doc.get("items", []):
        items.append({
            "item_code": itm.get("item_code"),
            "qty": float(itm.get("qty", 0))
        })
        
    ops = []
    for op in doc.get("operations", []):
        ops.append({
            "operation": op.get("operation"),
            "workstation": op.get("workstation"),
            "time_in_mins": float(op.get("time_in_mins", 0))
        })
        
    bom_info = {
        "name": latest_bom["name"],
        "operating_cost": float(doc.get("operating_cost", 0)),
        "with_operations": doc.get("with_operations", 0),
        "items": items,
        "operations": ops,
        "creation": doc.get("creation")
    }

# Read task start time
task_start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        try:
            task_start_time = int(f.read().strip())
        except:
            pass

result = {
    "task_start_time": task_start_time,
    "workstations": workstations,
    "operations": operations,
    "bom_submitted": bom_info is not None,
    "bom_info": bom_info
}

with open("/tmp/manufacturing_routing_and_bom_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/manufacturing_routing_and_bom_result.json ===")
PYEOF

echo "=== Export done ==="