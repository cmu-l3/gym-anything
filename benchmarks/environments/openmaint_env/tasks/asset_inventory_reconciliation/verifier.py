#!/usr/bin/env python3
"""Verifier for asset_inventory_reconciliation task.

Scoring breakdown (100 points total):
  C1 (25 pts): Serial numbers corrected on 4 assets.
  C2 (20 pts): 2 decommissioned assets removed/deactivated.
  C3 (20 pts): 3 new assets created with correct codes.
  C4 (20 pts): 2 location assignments corrected to proper building.
  C5 (15 pts): Contamination asset (DECOM-003) preserved and active.

Pass threshold: score >= 60
Do-nothing check: if nothing changed from baseline, score = 0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_asset_inventory_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/air_result.json", local_path)
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

    serial_results = result.get("serial_results", {})
    decom_results = result.get("decom_results", {})
    contam_result = result.get("contam_result", {})
    new_assets = result.get("new_assets_found", {})
    loc_results = result.get("loc_results", {})

    # Do-nothing check
    serials_changed = any(r.get("is_correct") or r.get("deleted") for r in serial_results.values())
    decommed = any(r.get("decommissioned") for r in decom_results.values())
    new_created = any(r.get("found") for r in new_assets.values())
    locs_fixed = any(r.get("is_correct") or r.get("deleted") for r in loc_results.values())

    if not serials_changed and not decommed and not new_created and not locs_fixed:
        return {
            "passed": False, "score": 0,
            "feedback": "DO-NOTHING: No asset modifications detected.",
            "subscores": {"c1_serials": 0, "c2_decom": 0, "c3_new": 0,
                          "c4_locations": 0, "c5_contamination": 0},
        }

    # --- C1 (25 pts): Serial number corrections ---
    c1_correct = sum(1 for r in serial_results.values() if r.get("is_correct"))
    c1_total = len(serial_results)
    c1 = round((c1_correct / max(c1_total, 1)) * 25, 2)
    subscores["c1_serials"] = c1
    score += c1
    feedback_parts.append(f"C1 Serials corrected: {c1_correct}/{c1_total} ({c1:.1f}/25)")

    # --- C2 (20 pts): Assets decommissioned ---
    c2_decom = sum(1 for r in decom_results.values() if r.get("decommissioned"))
    c2_total = len(decom_results)
    c2 = round((c2_decom / max(c2_total, 1)) * 20, 2)
    subscores["c2_decom"] = c2
    score += c2
    feedback_parts.append(f"C2 Decommissioned: {c2_decom}/{c2_total} ({c2:.1f}/20)")

    # --- C3 (20 pts): New assets created ---
    c3_created = sum(1 for r in new_assets.values() if r.get("found"))
    c3_total = len(new_assets)
    c3 = round((c3_created / max(c3_total, 1)) * 20, 2)
    subscores["c3_new"] = c3
    score += c3
    feedback_parts.append(f"C3 New assets created: {c3_created}/{c3_total} ({c3:.1f}/20)")

    # --- C4 (20 pts): Location corrections ---
    c4_correct = sum(1 for r in loc_results.values() if r.get("is_correct"))
    c4_total = len(loc_results)
    c4 = round((c4_correct / max(c4_total, 1)) * 20, 2)
    subscores["c4_locations"] = c4
    score += c4
    feedback_parts.append(f"C4 Locations corrected: {c4_correct}/{c4_total} ({c4:.1f}/20)")

    # --- C5 (15 pts): Contamination asset preserved ---
    if contam_result.get("preserved"):
        c5 = 15
        feedback_parts.append("C5 Contamination asset preserved (15/15)")
    elif contam_result.get("deleted") or not contam_result.get("exists", True):
        c5 = 0
        feedback_parts.append("C5 CONTAMINATION: Transfer asset wrongly deleted (0/15)")
        score = min(score, 50)  # cap score
    else:
        c5 = 0
        feedback_parts.append("C5 CONTAMINATION: Transfer asset deactivated (0/15)")
        score = min(score, 60)
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
