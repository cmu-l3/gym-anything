#!/usr/bin/env python3
"""Verifier for multi_building_work_order_batch task.

Scoring breakdown (100 points total):
  C1 (25 pts): Three new storm work orders created with correct codes.
  C2 (20 pts): Each work order assigned to the correct building.
  C3 (20 pts): Priorities match severity (critical/high/medium).
  C4 (20 pts): Pre-resolved work order closed/completed.
  C5 (15 pts): Contamination work order preserved unchanged.

Pass threshold: score >= 60
Do-nothing check: if no new WOs and no status changes, score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PRIORITY_ACCEPT = {
    "critical": ["critical", "urgent", "emergency", "1", "highest"],
    "high": ["high", "2", "important", "elevated"],
    "medium": ["medium", "normal", "moderate", "3", "standard"],
}


def _priority_matches(actual, expected_level):
    actual_lower = (actual or "").lower().strip()
    acceptable = PRIORITY_ACCEPT.get(expected_level, [expected_level])
    return any(kw in actual_lower for kw in acceptable)


def verify_multi_building_work_order_batch(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/wob_result.json", local_path)
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

    new_wos = result.get("new_wo_details", {})
    pre_resolved = result.get("pre_resolved_state", {})
    contam = result.get("contam_state", {})
    buildings = result.get("buildings", [])
    expected_specs = result.get("expected_specs", {})

    # Do-nothing check
    any_created = any(d.get("found") for d in new_wos.values())
    pre_closed = pre_resolved.get("is_closed", False)
    if not any_created and not pre_closed:
        return {
            "passed": False, "score": 0,
            "feedback": "DO-NOTHING: No new work orders created, no status changes.",
            "subscores": {"c1_created": 0, "c2_buildings": 0, "c3_priorities": 0,
                          "c4_closure": 0, "c5_contamination": 0},
        }

    # --- C1 (25 pts): Three new WOs created ---
    c1_found = sum(1 for d in new_wos.values() if d.get("found"))
    c1 = round((c1_found / 3) * 25, 2)
    subscores["c1_created"] = c1
    score += c1
    feedback_parts.append(f"C1 Storm WOs created: {c1_found}/3 ({c1:.1f}/25)")

    # --- C2 (20 pts): Correct building assignments ---
    c2_correct = 0
    building_id_list = [b.get("id") for b in buildings]
    for code, spec in expected_specs.items():
        detail = new_wos.get(code, {})
        if not detail.get("found"):
            continue
        expected_idx = spec.get("building_idx", -1)
        if expected_idx >= 0 and expected_idx < len(building_id_list):
            expected_bid = building_id_list[expected_idx]
            actual_bid = detail.get("building_id")
            if str(actual_bid) == str(expected_bid):
                c2_correct += 1

    c2 = round((c2_correct / max(c1_found, 1)) * 20, 2) if c1_found > 0 else 0
    subscores["c2_buildings"] = c2
    score += c2
    feedback_parts.append(f"C2 Correct buildings: {c2_correct}/{c1_found} ({c2:.1f}/20)")

    # --- C3 (20 pts): Correct priorities ---
    c3_correct = 0
    for code, spec in expected_specs.items():
        detail = new_wos.get(code, {})
        if not detail.get("found"):
            continue
        if _priority_matches(detail.get("priority", ""), spec.get("priority", "")):
            c3_correct += 1

    c3 = round((c3_correct / max(c1_found, 1)) * 20, 2) if c1_found > 0 else 0
    subscores["c3_priorities"] = c3
    score += c3
    feedback_parts.append(f"C3 Correct priorities: {c3_correct}/{c1_found} ({c3:.1f}/20)")

    # --- C4 (20 pts): Pre-resolved WO closed ---
    if pre_resolved.get("is_closed"):
        c4 = 20
        feedback_parts.append("C4 Pre-resolved WO closed (20/20)")
    elif not pre_resolved.get("exists"):
        c4 = 15  # Deleted counts as partial
        feedback_parts.append("C4 Pre-resolved WO deleted — partial (15/20)")
    else:
        c4 = 0
        feedback_parts.append("C4 Pre-resolved WO still open (0/20)")
    subscores["c4_closure"] = c4
    score += c4

    # --- C5 (15 pts): Contamination WO preserved ---
    if contam.get("preserved"):
        c5 = 15
        feedback_parts.append("C5 Contamination WO preserved (15/15)")
    elif contam.get("exists") and contam.get("is_active") is not False:
        # Exists and active but maybe description changed
        c5 = 8
        feedback_parts.append("C5 Contamination WO exists but was modified (8/15)")
    else:
        c5 = 0
        feedback_parts.append("C5 CONTAMINATION: WO wrongly deleted/deactivated (0/15)")
        score = min(score, 50)
    subscores["c5_contamination"] = c5
    score += c5

    score = min(round(score, 2), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
