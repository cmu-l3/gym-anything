#!/bin/bash
echo "=== Exporting update_ci_serial_numbers result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

python3 << 'PYEOF'
import sys, json
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

baseline = load_baseline("/tmp/serial_audit_baseline.json")
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
serial_field = baseline["serial_field"]
asset_ids = baseline["asset_ids"]
expected = baseline["expected_updates"]

result = {
    "assets": {},
    "updates_correct": 0,
    "notes_updated": 0,
    "total_expected": len(expected)
}

for code, card_id in asset_ids.items():
    card = get_card(server_cls, card_id, token)
    if card:
        current_serial = card.get(serial_field, "") or ""
        current_notes = card.get("Notes", "") or ""
        expected_serial = expected.get(code, "")

        serial_match = (current_serial == expected_serial)
        notes_has_audit = "Q1-2026 Audit" in current_notes or "audit" in current_notes.lower()

        if serial_match:
            result["updates_correct"] += 1
        if notes_has_audit:
            result["notes_updated"] += 1

        result["assets"][code] = {
            "id": card_id,
            "current_serial": current_serial,
            "expected_serial": expected_serial,
            "serial_match": serial_match,
            "notes": current_notes,
            "notes_has_audit": notes_has_audit
        }

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export: {result['updates_correct']}/{result['total_expected']} serials correct, {result['notes_updated']} notes updated")
PYEOF

echo "=== Export complete ==="
