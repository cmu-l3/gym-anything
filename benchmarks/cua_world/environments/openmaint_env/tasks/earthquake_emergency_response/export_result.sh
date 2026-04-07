#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Earthquake Emergency Response: Export ==="

# ── Final screenshot ────────────────────────────────────────────────
take_screenshot /tmp/eq_final_screenshot.png

# ── Collect post-task state via API ─────────────────────────────────
python3 << 'PYEOF'
import sys, json, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# ── Load baseline ───────────────────────────────────────────────────
baseline_path = "/tmp/eq_baseline.json"
if not os.path.exists(baseline_path):
    result = {"error": "baseline_not_found"}
    with open("/tmp/eq_result.json", "w") as f:
        json.dump(result, f, indent=2, default=str)
    sys.exit(0)

with open(baseline_path) as f:
    baseline = json.load(f)

if "error" in baseline:
    result = {"error": f"baseline_error: {baseline['error']}"}
    with open("/tmp/eq_result.json", "w") as f:
        json.dump(result, f, indent=2, default=str)
    sys.exit(0)

token = get_token()
if not token:
    result = {"error": "auth_failed"}
    with open("/tmp/eq_result.json", "w") as f:
        json.dump(result, f, indent=2, default=str)
    sys.exit(0)

building_cls       = baseline["building_cls"]
floor_cls          = baseline["floor_cls"]
room_cls           = baseline["room_cls"]
floor_ref_building = baseline["floor_ref_building"]
room_ref_floor     = baseline["room_ref_floor"]
wo_type            = baseline.get("wo_type")
wo_cls             = baseline.get("wo_cls")
priority_field     = baseline.get("priority_field")
building_field     = baseline.get("building_field")
existing_wo_ids    = baseline.get("existing_wo_ids", [])
existing_floor_ids = baseline.get("existing_floor_ids", [])
existing_room_ids  = baseline.get("existing_room_ids", [])

# ── 1. Current building state ───────────────────────────────────────
building_state = {}
for da in baseline["buildings"]:
    bid = da["id"]
    try:
        card = get_card(building_cls, bid, token)
        if card and card.get("_id"):
            building_state[da["code"]] = {
                "id":          bid,
                "code":        da["code"],
                "name":        card.get("Description", ""),
                "severity":    da["severity"],
                "is_eoc":      da.get("is_eoc", False),
                "original_description": da["original_description"],
            }
        else:
            building_state[da["code"]] = {"id": bid, "error": "card_not_found"}
    except Exception as e:
        building_state[da["code"]] = {"id": bid, "error": str(e)}

# ── 2. All work orders — identify new ones ──────────────────────────
new_work_orders = []
contam_wo_state = None

if wo_type and wo_cls:
    try:
        if wo_type == "process":
            all_wos = get_process_instances(wo_cls, token, limit=500)
        else:
            all_wos = get_cards(wo_cls, token, limit=500)

        subject_field = baseline.get("subject_field", "ShortDescr")
        for wo in all_wos:
            wid = wo.get("_id")
            subject_val = wo.get(subject_field, "") or wo.get("ShortDescr", "") or ""
            desc_val = wo.get("Description", "") or ""
            notes_val = wo.get("Notes", "") or ""
            full_text = f"{subject_val} {desc_val} {notes_val}"

            # Extract priority
            pval = wo.get(priority_field) if priority_field else None
            if isinstance(pval, dict):
                priority_str = pval.get("description", str(pval.get("_id", "")))
            else:
                priority_str = str(pval) if pval else ""

            # Extract building reference
            b_val = wo.get(building_field) if building_field else None
            b_id = b_val
            if isinstance(b_val, dict):
                b_id = b_val.get("_id")

            # Check contamination trap
            contam_subj = baseline.get("contam_wo_subject", "")
            if contam_subj and contam_subj.lower() in full_text.lower():
                contam_wo_state = {
                    "id":          wid,
                    "subject":     subject_val,
                    "description": desc_val,
                    "is_active":   wo.get("_is_active", True),
                    "subj_match":  subject_val == contam_subj,
                }
                continue

            # Also check by ID
            if wid == baseline.get("contam_wo_id"):
                contam_wo_state = {
                    "id":          wid,
                    "subject":     subject_val,
                    "description": desc_val,
                    "is_active":   wo.get("_is_active", True),
                    "subj_match":  subject_val == contam_subj,
                }
                continue

            # Skip baseline WOs
            if wid in existing_wo_ids:
                continue

            new_work_orders.append({
                "id":          wid,
                "subject":     subject_val,
                "description": desc_val,
                "notes":       notes_val,
                "priority":    priority_str.lower() if priority_str else "",
                "building_id": b_id,
            })
    except Exception as e:
        print(f"WARNING: Could not fetch work orders: {e}", file=sys.stderr)

# ── 3. All floors — identify new ones ──────────────────────────────
new_floors = []
try:
    all_floors = get_cards(floor_cls, token, limit=500)
    for fl in all_floors:
        fid = fl.get("_id")
        if fid in existing_floor_ids:
            continue

        # Extract building reference
        b_val = fl.get(floor_ref_building)
        b_id = b_val
        if isinstance(b_val, dict):
            b_id = b_val.get("_id")

        new_floors.append({
            "id":          fid,
            "code":        fl.get("Code", ""),
            "description": fl.get("Description", ""),
            "building_id": b_id,
        })
except Exception as e:
    print(f"WARNING: Could not fetch floors: {e}", file=sys.stderr)

# ── 4. All rooms — identify new ones ───────────────────────────────
new_rooms = []
try:
    all_rooms = get_cards(room_cls, token, limit=500)
    for rm in all_rooms:
        rid = rm.get("_id")
        if rid in existing_room_ids:
            continue

        # Extract floor reference
        f_val = rm.get(room_ref_floor)
        f_id = f_val
        if isinstance(f_val, dict):
            f_id = f_val.get("_id")

        new_rooms.append({
            "id":          rid,
            "code":        rm.get("Code", ""),
            "description": rm.get("Description", ""),
            "floor_id":    f_id,
        })
except Exception as e:
    print(f"WARNING: Could not fetch rooms: {e}", file=sys.stderr)

# ── 5. Build result ────────────────────────────────────────────────
result = {
    "buildings":        building_state,
    "new_work_orders":  new_work_orders,
    "new_floors":       new_floors,
    "new_rooms":        new_rooms,
    "contam_wo":        contam_wo_state,
    "baseline_summary": {
        "num_buildings":        len(baseline["buildings"]),
        "num_existing_wos":     len(existing_wo_ids),
        "num_existing_floors":  len(existing_floor_ids),
        "num_existing_rooms":   len(existing_room_ids),
        "eoc_building_id":      baseline["eoc_building_id"],
        "eoc_building_code":    baseline["eoc_building_code"],
    },
}

with open("/tmp/eq_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

os.chmod("/tmp/eq_result.json", 0o666)
print("Result saved to /tmp/eq_result.json")
PYEOF

echo "=== Export complete ==="
