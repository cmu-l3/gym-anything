#!/bin/bash
echo "=== Exporting Room Occupancy Audit Result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export data via Python
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

try:
    with open("/tmp/room_audit_baseline.json", "r") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("ERROR: Baseline file not found")
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed")
    sys.exit(0)

room_cls = baseline["room_class"]
room_ids = baseline["room_ids"]
seed_data = baseline["seed_data"]

results = {}

for code, card_id in room_ids.items():
    if not card_id:
        results[code] = {"error": "no_id"}
        continue
        
    card = get_card(room_cls, card_id, token)
    if not card:
        results[code] = {"error": "deleted"}
        continue
        
    current_notes = card.get("Notes", "")
    
    # Find expected ground truth
    expected = next((item["GroundTruth"] for item in seed_data if item["Code"] == code), "")
    initial = next((item["Notes"] for item in seed_data if item["Code"] == code), "")
    
    results[code] = {
        "current_notes": current_notes,
        "expected": expected,
        "initial": initial,
        "is_correct": current_notes.strip().lower() == expected.lower(),
        "changed": current_notes.strip() != initial.strip()
    }

final_output = {
    "rooms": results,
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0))
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_output, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="