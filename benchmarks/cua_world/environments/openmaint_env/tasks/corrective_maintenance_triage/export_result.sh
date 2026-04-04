#!/bin/bash
echo "=== Exporting corrective_maintenance_triage result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cmt_final_screenshot.png

python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
baseline = load_baseline("/tmp/cmt_baseline.json")
if not baseline:
    print("ERROR: Could not load baseline", file=sys.stderr)
    result = {"error": "baseline_missing"}
    with open("/tmp/cmt_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(0)

token = get_token()
if not token:
    result = {"error": "auth_failed"}
    with open("/tmp/cmt_result.json", "w") as f:
        json.dump(result, f)
    sys.exit(0)

ticket_type = baseline.get("ticket_type", "card")
ticket_cls = baseline.get("ticket_class")
seeded_ids = baseline.get("seeded_ids", {})
tickets_spec = baseline.get("tickets_spec", {})
priority_field = baseline.get("priority_field")
category_field = baseline.get("category_field")
status_field = baseline.get("status_field")
assignee_field = baseline.get("assignee_field")

# Query current state of each seeded ticket
ticket_states = {}
for tag, card_id in seeded_ids.items():
    if not card_id:
        ticket_states[tag] = {"error": "no_id"}
        continue
    card = get_record(ticket_type, ticket_cls, card_id, token)
    if not card:
        ticket_states[tag] = {"deleted_or_missing": True}
        continue

    state = {
        "id": card_id,
        "code": card.get("Code", ""),
        "description": card.get("Description", ""),
    }

    # Read priority
    if priority_field:
        pval = card.get(priority_field)
        if isinstance(pval, dict):
            state["priority"] = (pval.get("description", "") or pval.get("code", "") or str(pval.get("_id", ""))).lower()
        else:
            state["priority"] = str(pval).lower() if pval else ""

    # Read category
    if category_field:
        cval = card.get(category_field)
        if isinstance(cval, dict):
            state["category"] = (cval.get("description", "") or cval.get("code", "") or str(cval.get("_id", ""))).lower()
        else:
            state["category"] = str(cval).lower() if cval else ""

    # Read status
    if status_field:
        sval = card.get(status_field)
        if isinstance(sval, dict):
            state["status"] = (sval.get("description", "") or sval.get("code", "") or str(sval.get("_id", ""))).lower()
        else:
            state["status"] = str(sval).lower() if sval else ""
    # Also check the system _status field
    state["flow_status"] = str(card.get("_card_status", card.get("FlowStatus", ""))).lower()

    # Read assignee
    if assignee_field:
        aval = card.get(assignee_field)
        if isinstance(aval, dict):
            state["assignee"] = aval.get("description", "") or aval.get("_id", "")
        elif aval:
            state["assignee"] = str(aval)
        else:
            state["assignee"] = ""
    else:
        state["assignee"] = ""

    # Check if card is still active
    state["is_active"] = card.get("_is_active", True)

    ticket_states[tag] = state

# Also check original ticket
original_id = baseline.get("original_ticket_id")
original_state = {}
if original_id:
    card = get_record(ticket_type, ticket_cls, original_id, token)
    if card:
        original_state = {
            "id": original_id,
            "code": card.get("Code", ""),
            "is_active": card.get("_is_active", True),
        }

result = {
    "ticket_class": ticket_cls,
    "seeded_ids": seeded_ids,
    "tickets_spec": tickets_spec,
    "ticket_states": ticket_states,
    "original_ticket_state": original_state,
    "priority_field": priority_field,
    "category_field": category_field,
    "status_field": status_field,
    "assignee_field": assignee_field,
}

with open("/tmp/cmt_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result saved to /tmp/cmt_result.json")
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== corrective_maintenance_triage export complete ==="
