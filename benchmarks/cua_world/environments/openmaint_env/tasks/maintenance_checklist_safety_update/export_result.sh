#!/bin/bash
echo "=== Exporting maintenance_checklist_safety_update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
try:
    with open("/tmp/safety_update_baseline.json", "r") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("ERROR: Baseline file not found")
    sys.exit(1)

token = get_token()
if not token:
    print("ERROR: Auth failed")
    sys.exit(1)

pm_cls = baseline["pm_cls"]
pm_type = baseline["pm_type"] # likely 'card'
duration_field = baseline["duration_field"]
seeded_ids = baseline["seeded_ids"]
initial_states = baseline["initial_states"]

current_states = {}

for code, card_id in seeded_ids.items():
    card = get_card(pm_cls, card_id, token)
    if not card:
        current_states[code] = {"exists": False}
        continue

    desc = card.get("Description", "")
    dur = card.get(duration_field, 0)
    
    # Handle duration if it returns a dictionary (some lookups) or string
    if isinstance(dur, dict):
        dur = dur.get("code", 0) # simplified fallback
    
    try:
        dur_int = int(dur)
    except (ValueError, TypeError):
        dur_int = 0

    current_states[code] = {
        "exists": True,
        "description": desc,
        "duration": dur_int
    }

result = {
    "baseline": initial_states,
    "current": current_states,
    "duration_field_used": duration_field
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete")
PYEOF