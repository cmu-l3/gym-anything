#!/usr/bin/env python3
"""Verifier for preventive_maintenance_schedule_setup task.

Scoring breakdown (100 points total):
  C1 (25 pts): Three new PM activity cards created with correct Code pattern.
  C2 (25 pts): Each PM activity references a different building.
  C3 (20 pts): Each PM includes all 5 required task items in description/notes.
  C4 (15 pts): Priority set to medium/normal on all new PMs.
  C5 (15 pts): Existing maintenance records preserved (not deleted).

Pass threshold: score >= 60
Do-nothing check: if no new PMs created, score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

REQUIRED_TASKS = ["filter", "coil", "refrigerant", "thermostat", "condensate"]
MEDIUM_KEYWORDS = ["medium", "normal", "moderate", "2", "standard"]


def verify_preventive_maintenance_schedule_setup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/pm_result.json", local_path)
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

    new_pms = result.get("new_pm_details", [])
    buildings = result.get("buildings", [])

    # Do-nothing check
    if len(new_pms) == 0:
        return {
            "passed": False, "score": 0,
            "feedback": "DO-NOTHING: No new PM activities created.",
            "subscores": {"c1_created": 0, "c2_buildings": 0, "c3_tasks": 0,
                          "c4_priority": 0, "c5_preserved": 0},
        }

    # --- C1 (25 pts): Three new PMs with correct Code pattern ---
    correct_codes = sum(1 for pm in new_pms if pm.get("code_matches_pattern"))
    # Score based on how many of 3 expected PMs exist
    c1_count = min(len(new_pms), 3)
    c1_code_bonus = min(correct_codes, 3)
    # Base: 15 pts for creating 3 PMs, +10 for correct codes
    c1_base = round((c1_count / 3) * 15, 2)
    c1_code = round((c1_code_bonus / 3) * 10, 2)
    c1 = c1_base + c1_code
    subscores["c1_created"] = c1
    score += c1
    feedback_parts.append(f"C1 PMs created: {c1_count}/3, codes correct: {c1_code_bonus}/3 ({c1:.1f}/25)")

    # --- C2 (25 pts): Each PM references a different building ---
    building_refs = set()
    for pm in new_pms:
        bid = pm.get("building_id")
        if bid:
            building_refs.add(bid)

    building_id_set = set(b.get("id") for b in buildings if b.get("id"))
    valid_refs = building_refs & building_id_set
    c2 = round((min(len(valid_refs), 3) / 3) * 25, 2)
    subscores["c2_buildings"] = c2
    score += c2
    feedback_parts.append(f"C2 Distinct buildings referenced: {len(valid_refs)}/3 ({c2:.1f}/25)")

    # --- C3 (20 pts): Task items in description/notes ---
    c3_per_pm = []
    for pm in new_pms[:3]:  # Score top 3
        items_found = pm.get("task_items_found", [])
        c3_per_pm.append(len(items_found))

    if c3_per_pm:
        avg_items = sum(c3_per_pm) / len(c3_per_pm)
        c3 = round((avg_items / len(REQUIRED_TASKS)) * 20, 2)
    else:
        c3 = 0
    subscores["c3_tasks"] = c3
    score += c3
    items_str = "/".join(str(x) for x in c3_per_pm[:3])
    feedback_parts.append(f"C3 Task items per PM: [{items_str}]/{len(REQUIRED_TASKS)} each ({c3:.1f}/20)")

    # --- C4 (15 pts): Priority set to medium/normal ---
    c4_correct = 0
    for pm in new_pms[:3]:
        prio = (pm.get("priority", "") or "").lower()
        if any(kw in prio for kw in MEDIUM_KEYWORDS):
            c4_correct += 1
    c4 = round((c4_correct / max(min(len(new_pms), 3), 1)) * 15, 2)
    subscores["c4_priority"] = c4
    score += c4
    feedback_parts.append(f"C4 Medium priority: {c4_correct}/{min(len(new_pms), 3)} ({c4:.1f}/15)")

    # --- C5 (15 pts): Existing records preserved ---
    expected_existing = result.get("expected_existing_count", 0)
    preserved = result.get("existing_preserved_count", 0)
    if expected_existing == 0:
        c5 = 15  # No existing records to preserve
    else:
        c5 = round((preserved / expected_existing) * 15, 2)
    subscores["c5_preserved"] = c5
    score += c5
    feedback_parts.append(f"C5 Existing preserved: {preserved}/{expected_existing} ({c5:.1f}/15)")

    score = min(round(score, 2), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
