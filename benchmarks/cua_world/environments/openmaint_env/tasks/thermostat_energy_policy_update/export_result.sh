#!/bin/bash
echo "=== Exporting result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data via Python
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
try:
    with open("/tmp/thermostat_baseline.json", "r") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("Baseline not found, creating error result")
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": "Baseline missing"}, f)
    sys.exit(0)

token = get_token()
if not token:
    with open("/tmp/task_result.json", "w") as f:
        json.dump({"error": "Auth failed"}, f)
    sys.exit(0)

cls_name = baseline["asset_class"]
notes_field = baseline["notes_field"]
assets_map = baseline["assets"]

results = {}

for code, info in assets_map.items():
    card_id = info["id"]
    card = get_card(cls_name, card_id, token)
    
    actual_notes = ""
    if card:
        val = card.get(notes_field)
        if val:
            actual_notes = str(val)
    
    results[code] = {
        "id": card_id,
        "is_smart": info["is_smart"],
        "building_id": info["building_id"],
        "expected_action": info["expected_action"],
        "actual_notes": actual_notes
    }

output = {
    "baseline": baseline,
    "results": results,
    "timestamp": os.popen("date +%s").read().strip()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export complete ==="