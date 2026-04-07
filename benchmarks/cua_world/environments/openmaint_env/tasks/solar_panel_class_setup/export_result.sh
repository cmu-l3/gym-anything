#!/bin/bash
echo "=== Exporting solar_panel_class_setup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/sp_final_screenshot.png

# Run Python inspection script
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/sp_baseline.json")
if not baseline:
    with open("/tmp/sp_result.json", "w") as f:
        json.dump({"error": "baseline_missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/sp_result.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

initial_classes = set(baseline.get("initial_class_names", []))

# 1. FIND THE NEW CLASS
# Agent might name it "SolarPanel", "Solar_Panel", etc.
all_classes = list_classes(token)
found_class = None
found_class_name = ""

for c in all_classes:
    cname = c.get("_id", "")
    cdesc = c.get("description", "")
    # Check if name contains "solar" (case insensitive) and wasn't in baseline
    if "solar" in cname.lower() or "solar" in cdesc.lower():
        if cname not in initial_classes:
            found_class = c
            found_class_name = cname
            break

class_result = {
    "found": False,
    "name": "",
    "active": False,
    "parent": ""
}

attributes_result = {}
records_result = []
building_links_valid = 0

if found_class:
    class_result["found"] = True
    class_result["name"] = found_class_name
    class_result["active"] = found_class.get("active", True)
    class_result["parent"] = found_class.get("superclass", "")

    # 2. CHECK ATTRIBUTES
    attrs = get_class_attributes(found_class_name, token)
    
    # We look for fuzzy matches on attribute names
    expected_attrs = {
        "PanelCapacityKW": ["decimal", "double", "float"],
        "InstallationDate": ["date"],
        "Manufacturer": ["string", "text", "char"],
        "InverterType": ["string", "text", "char"],
        "PanelCount": ["integer", "int"]
    }

    for exp_name, allowed_types in expected_attrs.items():
        match_found = False
        actual_type = ""
        
        for a in attrs:
            aname = a.get("_id", "").lower()
            atype = a.get("type", "").lower()
            
            # Simple fuzzy match: ignore case and underscores
            clean_exp = exp_name.lower().replace("_", "")
            clean_act = aname.replace("_", "")
            
            if clean_exp in clean_act:
                match_found = True
                actual_type = atype
                break
        
        # Check if type is correct
        type_correct = False
        if match_found:
            for t in allowed_types:
                if t in actual_type:
                    type_correct = True
                    break
        
        attributes_result[exp_name] = {
            "found": match_found,
            "type": actual_type,
            "type_correct": type_correct
        }

    # 3. CHECK RECORDS
    # Try to get cards for this class
    cards = get_cards(found_class_name, token)
    
    for card in cards:
        rec = {
            "code": card.get("Code", ""),
            "building_id": None,
            "attributes": {}
        }
        
        # Check building link
        # Need to find which attribute links to building
        # Usually it's "Building" or "Location" or inherited "Building"
        bld_ref = card.get("Building") or card.get("Location")
        if isinstance(bld_ref, dict):
            rec["building_id"] = bld_ref.get("_id")
        elif bld_ref:
            rec["building_id"] = bld_ref
            
        # Check if building ID is valid (exists in baseline buildings)
        valid_bld_ids = [b["id"] for b in baseline.get("buildings", [])]
        if rec["building_id"] in valid_bld_ids:
            building_links_valid += 1
            
        # Capture attribute values for verification
        # Iterate over our expected attrs and try to find values in the card
        for exp_name in expected_attrs.keys():
            # Find the actual attribute name used by the agent
            actual_attr_name = None
            for a in attrs:
                clean_exp = exp_name.lower().replace("_", "")
                clean_act = a.get("_id", "").lower().replace("_", "")
                if clean_exp in clean_act:
                    actual_attr_name = a.get("_id")
                    break
            
            if actual_attr_name:
                rec["attributes"][exp_name] = card.get(actual_attr_name)
                
        records_result.append(rec)

# 4. PRESERVATION CHECK
current_class_count = len(all_classes)
preservation_ok = current_class_count >= baseline.get("initial_class_count", 0)

result = {
    "class_result": class_result,
    "attributes_result": attributes_result,
    "records_result": records_result,
    "building_links_valid": building_links_valid,
    "preservation_ok": preservation_ok,
    "baseline_buildings": baseline.get("buildings", [])
}

with open("/tmp/sp_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)
    
print("Export complete.")
PYEOF