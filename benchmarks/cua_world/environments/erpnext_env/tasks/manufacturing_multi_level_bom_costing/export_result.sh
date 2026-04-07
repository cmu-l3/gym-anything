#!/bin/bash
# Export script for manufacturing_multi_level_bom_costing task
# Queries ERPNext for the sub-assembly and parent items, and their respective BOMs.

echo "=== Exporting manufacturing_multi_level_bom_costing results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot as evidence
take_screenshot /tmp/manufacturing_multi_level_bom_costing_final.png 2>/dev/null || true

python3 << 'PYEOF'
import requests, json, sys

ERPNEXT_URL = "http://localhost:8080"
session = requests.Session()

# --- Login ---
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
    return session.get(f"{ERPNEXT_URL}/api/resource/{doctype}", params=params).json().get("data", [])

def get_doc(doctype, name):
    resp = session.get(f"{ERPNEXT_URL}/api/resource/{doctype}/{name}")
    return resp.json().get("data", {})

result = {
    "premium_rotor_exists": False,
    "premium_wind_turbine_exists": False,
    "rotor_boms": [],
    "turbine_boms": []
}

# Check Items
rotor_item = api_get("Item", [["item_code", "=", "Premium Rotor"]])
if rotor_item:
    result["premium_rotor_exists"] = True

turbine_item = api_get("Item", [["item_code", "=", "Premium Wind Turbine"]])
if turbine_item:
    result["premium_wind_turbine_exists"] = True

# Fetch Rotor BOMs
rotor_bom_list = api_get("BOM", [["item", "=", "Premium Rotor"], ["docstatus", "=", 1]])
for b in rotor_bom_list:
    doc = get_doc("BOM", b["name"])
    result["rotor_boms"].append({
        "name": doc.get("name"),
        "raw_material_cost": doc.get("raw_material_cost", 0),
        "total_cost": doc.get("total_cost", 0),
        "items": [{"item_code": i.get("item_code"), "qty": i.get("qty")} for i in doc.get("items", [])]
    })

# Fetch Turbine BOMs
turbine_bom_list = api_get("BOM", [["item", "=", "Premium Wind Turbine"], ["docstatus", "=", 1]])
for b in turbine_bom_list:
    doc = get_doc("BOM", b["name"])
    result["turbine_boms"].append({
        "name": doc.get("name"),
        "raw_material_cost": doc.get("raw_material_cost", 0),
        "total_cost": doc.get("total_cost", 0),
        "items": [{"item_code": i.get("item_code"), "qty": i.get("qty")} for i in doc.get("items", [])]
    })

with open("/tmp/manufacturing_multi_level_bom_costing_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
print("\n=== Export complete: /tmp/manufacturing_multi_level_bom_costing_result.json ===")
PYEOF

chmod 666 /tmp/manufacturing_multi_level_bom_costing_result.json 2>/dev/null || sudo chmod 666 /tmp/manufacturing_multi_level_bom_costing_result.json 2>/dev/null || true

echo "=== Export done ==="