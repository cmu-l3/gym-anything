#!/bin/bash
echo "=== Exporting register_new_server_ci result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/register_server_baseline.json")
if not baseline:
    print("ERROR: Baseline not found", file=sys.stderr)
    json.dump({"error": "no_baseline"}, open("/tmp/task_result.json", "w"))
    sys.exit(0)

token = get_token()
if not token:
    print("ERROR: Auth failed", file=sys.stderr)
    json.dump({"error": "auth_failed"}, open("/tmp/task_result.json", "w"))
    sys.exit(0)

server_cls = baseline["server_class"]
initial_count = baseline["initial_count"]
expected_code = baseline["expected_code"]

result = {
    "server_class": server_cls,
    "initial_count": initial_count,
    "current_count": 0,
    "new_card_found": False,
    "card_data": {}
}

if server_cls != "UNKNOWN":
    result["current_count"] = count_cards(server_cls, token)

    # Search for the newly created card by Code
    cards = get_cards(server_cls, token, limit=200)
    for card in cards:
        code = card.get("Code", "") or ""
        if expected_code in code:
            result["new_card_found"] = True
            result["card_data"] = {
                "id": card.get("_id"),
                "Code": card.get("Code", ""),
                "Description": card.get("Description", ""),
                "SerialNumber": card.get("SerialNumber", "") or card.get("Serial", "") or "",
                "Notes": card.get("Notes", "") or ""
            }
            break

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export: found={result['new_card_found']}, count_delta={result['current_count'] - initial_count}")
PYEOF

echo "=== Export complete ==="
