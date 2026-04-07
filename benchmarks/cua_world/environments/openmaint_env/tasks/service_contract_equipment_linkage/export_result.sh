#!/bin/bash
echo "=== Exporting service_contract_equipment_linkage result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/sce_final_screenshot.png

# Run Python export logic
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/sce_baseline.json")
if not baseline:
    print("ERROR: Baseline missing", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    result = {"error": "auth_failed"}
    with open("/tmp/sce_result.json", "w") as f: json.dump(result, f)
    sys.exit(0)

asset_cls = baseline.get("asset_class")
contract_cls = baseline.get("contract_class")
contam_id = baseline.get("contam_id")

# 1. Fetch created CIs
# --------------------
target_cis = ["EQ-CHILLER-010", "EQ-AHU-015", "EQ-ELEV-007"]
found_cis = {}

for code in target_cis:
    # Manual filter in python to be robust against API filter syntax variations
    all_cis = get_cards(asset_cls, token, limit=1000)
    match = next((c for c in all_cis if c.get("Code") == code), None)
    
    if match:
        # Get full details
        full_card = get_card(asset_cls, match["_id"], token)
        found_cis[code] = {
            "exists": True,
            "id": match["_id"],
            "description": full_card.get("Description", ""),
            "serial": full_card.get("SerialNumber", ""),
            "building_ref": str(full_card.get("Building", "")) # Capture raw ref
        }
    else:
        found_cis[code] = {"exists": False}

# 2. Fetch created Contracts
# --------------------------
target_contracts = ["SVC-2025-HVAC-001", "SVC-2025-ELEV-001", "SVC-2025-FIRE-001"]
found_contracts = {}

for code in target_contracts:
    all_contracts = get_cards(contract_cls, token, limit=1000)
    match = next((c for c in all_contracts if c.get("Code") == code), None)
    
    if match:
        full_card = get_card(contract_cls, match["_id"], token)
        found_contracts[code] = {
            "exists": True,
            "id": match["_id"],
            "description": full_card.get("Description", ""),
            "start_date": full_card.get("BeginDate", full_card.get("StartDate", "")),
            "end_date": full_card.get("EndDate", ""),
            "raw_data": str(full_card) # Capture all data to search for links
        }
    else:
        found_contracts[code] = {"exists": False}

# 3. Check Contamination (EQ-BOILER-003)
# --------------------------------------
contam_status = {"linked_to_contract": False, "exists": False}
if contam_id:
    card = get_card(asset_cls, contam_id, token)
    if card:
        contam_status["exists"] = True
        # Check if modified or linked.
        # Hard to check relations inverse from Asset without domain knowledge.
        # But we can check if it appears in any of the NEW contracts' raw data.
        contam_status["raw_data"] = str(card)
    else:
        contam_status["exists"] = False # Deleted?

# Check linkages via text search in contract data (robust fallback)
# If a contract references a CI, the CI's ID or Code usually appears in the contract's attributes
linkages = {}
for c_code, c_data in found_contracts.items():
    if not c_data["exists"]: continue
    
    links = []
    c_raw = c_data["raw_data"]
    
    # Check for target CIs
    for ci_code, ci_data in found_cis.items():
        if ci_data["exists"]:
            # Check for Code or ID in contract data
            if ci_code in c_raw or ci_data["id"] in c_raw:
                links.append(ci_code)
    
    # Check for contamination
    if contam_id and (contam_id in c_raw or "EQ-BOILER-003" in c_raw):
        contam_status["linked_to_contract"] = True
        contam_status["linked_to"] = c_code
        
    linkages[c_code] = links

result = {
    "cis": found_cis,
    "contracts": found_contracts,
    "linkages": linkages,
    "contamination": contam_status
}

with open("/tmp/sce_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="