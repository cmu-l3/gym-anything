#!/bin/bash
echo "=== Exporting corporate_art_collection_update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export data using Python
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load setup info
try:
    with open("/tmp/art_task_setup.json", "r") as f:
        setup_info = json.load(f)
    asset_cls = setup_info.get("asset_class")
    building_field = setup_info.get("building_field")
except Exception as e:
    print(f"ERROR: Could not load setup info: {e}", file=sys.stderr)
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    sys.exit(0)

# Define items to check
items_to_check = ["ART-NEW-001", "ART-NEW-002", "ART-NEW-003", "ART-OLD-004"]
results = {}

for code in items_to_check:
    # Search for card by Code
    # We fetch all cards and filter because filter syntax can be tricky/version-dependent
    # A cleaner way is using filter if confident, but getting all recent is safer for small datasets
    cards = get_cards(asset_cls, token, limit=1000) 
    found_card = None
    for c in cards:
        if c.get("Code") == code:
            found_card = c
            break
            
    if found_card:
        # Get full details
        card_detail = get_card(asset_cls, found_card["_id"], token)
        
        # Resolve Building reference
        bld_ref = card_detail.get(building_field)
        bld_desc = ""
        if isinstance(bld_ref, dict):
            bld_desc = bld_ref.get("Description", "")
        
        # Get Status
        # Status might be a lookup or a simple string depending on configuration
        status_val = card_detail.get("Status", "")
        if isinstance(status_val, dict):
            status_val = status_val.get("Description", "") or status_val.get("Code", "")
            
        results[code] = {
            "exists": True,
            "description": card_detail.get("Description", ""),
            "notes": card_detail.get("Notes", ""),
            "building": bld_desc,
            "status": str(status_val),
            "raw": card_detail # Debug info
        }
    else:
        results[code] = {
            "exists": False
        }

# Basic stats
all_assets_count = count_cards(asset_cls, token)

export_data = {
    "assets": results,
    "total_count": all_assets_count,
    "setup_info": setup_info
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(export_data, f, indent=2)

print("Export complete.")
PYEOF

# Add standard metadata
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Append timestamp info (using jq to merge would be cleaner, but simple append works for verifier reading separate file or we rely on python above)
# We will just rely on the python script's output for the main data.

echo "=== Export complete ==="