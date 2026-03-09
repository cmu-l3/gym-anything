#!/usr/bin/env python3
"""Verifier for building_commissioning_data_entry task.

Scoring breakdown (100 points total):
  C1 (20 pts): Building record created with correct Code and Description.
  C2 (20 pts): 4 Floor records created and linked to the building.
  C3 (25 pts): 12 Room records created and linked to correct floors.
  C4 (20 pts): 6 Asset records created with correct serial numbers.
  C5 (15 pts): Existing demo data preserved (buildings, floors, rooms, assets).

Pass threshold: score >= 60
Do-nothing check: if no new records created, score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_building_commissioning_data_entry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/bcd_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False, "score": 0,
            "feedback": f"Could not retrieve result file: {e}", "subscores": {},
        }

    if result.get("error"):
        return {
            "passed": False, "score": 0,
            "feedback": f"Export error: {result['error']}", "subscores": {},
        }

    building = result.get("building_found", {})
    floors = result.get("floor_results", {})
    rooms = result.get("room_results", {})
    assets = result.get("asset_results", {})
    preservation = result.get("preservation", {})

    # Do-nothing check
    bld_created = building.get("found", False)
    floors_created = sum(1 for f in floors.values() if f.get("found"))
    rooms_created = sum(1 for r in rooms.values() if r.get("found"))
    assets_created = sum(1 for a in assets.values() if a.get("found"))

    if not bld_created and floors_created == 0 and rooms_created == 0 and assets_created == 0:
        return {
            "passed": False, "score": 0,
            "feedback": "DO-NOTHING: No new records created.",
            "subscores": {"c1_building": 0, "c2_floors": 0, "c3_rooms": 0,
                          "c4_assets": 0, "c5_preserved": 0},
        }

    # --- C1 (20 pts): Building created ---
    if bld_created:
        desc = (building.get("description", "") or "").lower()
        has_westpark = "westpark" in desc
        c1 = 20 if has_westpark else 15  # partial if wrong description
        feedback_parts.append(f"C1 Building created (desc match: {has_westpark}) ({c1}/20)")
    else:
        c1 = 0
        feedback_parts.append("C1 Building NOT created (0/20)")
    subscores["c1_building"] = c1
    score += c1

    # --- C2 (20 pts): Floors created and linked ---
    floors_found = sum(1 for f in floors.values() if f.get("found"))
    floors_linked = sum(1 for f in floors.values() if f.get("linked_to_building"))
    # 10 pts for creation, 10 pts for linkage
    c2_create = round((floors_found / 4) * 10, 2)
    c2_link = round((floors_linked / max(floors_found, 1)) * 10, 2) if floors_found > 0 else 0
    c2 = c2_create + c2_link
    subscores["c2_floors"] = c2
    score += c2
    feedback_parts.append(f"C2 Floors: {floors_found}/4 created, {floors_linked} linked ({c2:.1f}/20)")

    # --- C3 (25 pts): Rooms created and linked to correct floors ---
    rooms_found = sum(1 for r in rooms.values() if r.get("found"))
    rooms_linked = sum(1 for r in rooms.values() if r.get("linked_to_correct_floor"))
    # 15 pts for creation, 10 pts for correct floor linkage
    c3_create = round((rooms_found / 12) * 15, 2)
    c3_link = round((rooms_linked / max(rooms_found, 1)) * 10, 2) if rooms_found > 0 else 0
    c3 = c3_create + c3_link
    subscores["c3_rooms"] = c3
    score += c3
    feedback_parts.append(f"C3 Rooms: {rooms_found}/12 created, {rooms_linked} linked correctly ({c3:.1f}/25)")

    # --- C4 (20 pts): Assets created with correct serials ---
    assets_found = sum(1 for a in assets.values() if a.get("found"))
    serials_correct = sum(1 for a in assets.values() if a.get("serial_correct"))
    assets_linked = sum(1 for a in assets.values() if a.get("linked_to_building"))
    # 10 pts for creation, 5 pts for serials, 5 pts for building link
    c4_create = round((assets_found / 6) * 10, 2)
    c4_serial = round((serials_correct / max(assets_found, 1)) * 5, 2) if assets_found > 0 else 0
    c4_link = round((assets_linked / max(assets_found, 1)) * 5, 2) if assets_found > 0 else 0
    c4 = c4_create + c4_serial + c4_link
    subscores["c4_assets"] = c4
    score += c4
    feedback_parts.append(
        f"C4 Assets: {assets_found}/6 created, {serials_correct} serials correct, "
        f"{assets_linked} linked ({c4:.1f}/20)"
    )

    # --- C5 (15 pts): Existing data preserved ---
    pres = preservation
    total_expected = 0
    total_preserved = 0
    for category in ["buildings", "floors", "rooms", "assets"]:
        cat_data = pres.get(category, {})
        expected = cat_data.get("expected", 0)
        preserved = cat_data.get("preserved", 0)
        total_expected += expected
        total_preserved += preserved

    if total_expected == 0:
        c5 = 15
    else:
        ratio = total_preserved / total_expected
        c5 = round(ratio * 15, 2)
        if ratio < 0.9:
            feedback_parts.append(f"C5 WARNING: Existing data deleted ({total_preserved}/{total_expected} preserved)")
            score = min(score, 60)  # Cap if significant deletion

    subscores["c5_preserved"] = c5
    score += c5
    if c5 >= 14:
        feedback_parts.append(f"C5 Existing data preserved ({c5:.1f}/15)")
    else:
        feedback_parts.append(f"C5 Existing data: {total_preserved}/{total_expected} preserved ({c5:.1f}/15)")

    score = min(round(score, 2), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
