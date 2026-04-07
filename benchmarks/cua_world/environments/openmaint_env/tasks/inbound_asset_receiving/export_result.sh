#!/bin/bash
echo "=== Exporting inbound_asset_receiving result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export result using Python
python3 << 'PYEOF'
import sys, json, os, time
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/iar_baseline.json")

token = get_token()
if not token:
    result = {"error": "auth_failed"}
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(0)

# Define expected data points
valid_serials = ["8H29F2X", "CN-0Y9N-71618-88A-123", "CN-0Y9N-71618-88A-124"]
damaged_serial = "9J30G3Y"
backorder_serial = "BC-1122-3344"

all_target_serials = valid_serials + [damaged_serial, backorder_serial]

# Search for these assets across likely classes
candidate_classes = ["Computer", "Equipment", "Asset", "CI", "Peripheral", "Monitor"]
found_assets = {}

# Initialize all as not found
for s in all_target_serials:
    found_assets[s] = {
        "exists": False,
        "class": None,
        "code": None,
        "description": None,
        "status": None
    }

# Query classes
for cls in candidate_classes:
    real_cls = find_class(cls, token)
    if not real_cls:
        continue
    
    # Get all cards (limit 500 should be enough for demo env)
    cards = get_cards(real_cls, token, limit=500)
    
    for card in cards:
        # Normalize serial lookup
        serial_val = (card.get("SerialNumber") or card.get("Serial") or card.get("SN") or "").strip()
        
        if serial_val in all_target_serials:
            found_assets[serial_val]["exists"] = True
            found_assets[serial_val]["class"] = real_cls
            found_assets[serial_val]["code"] = card.get("Code")
            found_assets[serial_val]["description"] = card.get("Description")
            
            # Handle Status lookup
            status_raw = card.get("Status") or card.get("_card_status")
            if isinstance(status_raw, dict):
                found_assets[serial_val]["status"] = status_raw.get("description", str(status_raw))
            else:
                found_assets[serial_val]["status"] = str(status_raw)

# Check Rejection Log File
log_path = "/home/ga/Desktop/rejection_log.txt"
log_exists = os.path.exists(log_path)
log_content = ""
if log_exists:
    with open(log_path, 'r') as f:
        log_content = f.read()

# Construct final result object
result = {
    "assets": found_assets,
    "rejection_log": {
        "exists": log_exists,
        "content": log_content
    },
    "timestamp": int(time.time())
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="