#!/usr/bin/env python3
"""Verifier for office_closure_asset_transfer task.

Scoring breakdown (100 points):
  C1: London assets relocated to NYC (25 pts)
  C2: Checked-out London assets were checked in (15 pts)
  C3: Relocation notes added to transferred assets (15 pts)
  C4: New assets ASSET-D004 and ASSET-M004 created at NYC (20 pts)
  C5: Non-London assets unchanged (15 pts)
  C6: No assets remain at London (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/office_closure_asset_transfer_result.json"


def verify_office_closure_asset_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    initial_london = int(result.get("initial_london_count", 0))
    relocated_assets = result.get("relocated_assets", [])

    # --- Do-nothing gate ---
    remaining = int(result.get("remaining_london_count", initial_london))
    if remaining == initial_london and initial_london > 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No London assets were relocated."}

    # --- C1: London assets relocated to NYC (25 pts) ---
    relocated_count = 0
    for asset in relocated_assets:
        if asset.get("found") and asset.get("location") == "New York Office":
            relocated_count += 1

    if initial_london > 0:
        ratio = relocated_count / initial_london
        c1_score = int(25 * ratio)
        score += c1_score
        feedback.append(f"C1: {relocated_count}/{initial_london} London assets relocated to NYC (+{c1_score})")
    else:
        feedback.append("C1: No London assets existed (skipped)")

    # --- C2: Checked-out London assets were checked in (15 pts) ---
    checked_out_str = result.get("initial_london_checked_out", "")
    if checked_out_str:
        checked_out_tags = [t.strip() for t in checked_out_str.split(",") if t.strip()]
        checked_in_count = 0
        for asset in relocated_assets:
            if asset.get("tag") in checked_out_tags and asset.get("is_checked_in"):
                checked_in_count += 1
        if checked_out_tags:
            ratio = checked_in_count / len(checked_out_tags)
            c2_score = int(15 * ratio)
            score += c2_score
            feedback.append(f"C2: {checked_in_count}/{len(checked_out_tags)} checked-out assets were checked in (+{c2_score})")
        else:
            score += 15
            feedback.append("C2: No checked-out London assets (full credit +15)")
    else:
        score += 15
        feedback.append("C2: No checked-out London assets (full credit +15)")

    # --- C3: Relocation notes added (15 pts) ---
    note_count = int(result.get("relocation_note_count", 0))
    if initial_london > 0:
        ratio = note_count / initial_london
        c3_score = int(15 * ratio)
        score += c3_score
        feedback.append(f"C3: {note_count}/{initial_london} transferred assets have RELOCATED note (+{c3_score})")
    else:
        feedback.append("C3: No London assets existed (skipped)")

    # --- C4: New assets created at NYC (20 pts) ---
    d004 = result.get("new_asset_d004", {})
    m004 = result.get("new_asset_m004", {})
    c4_score = 0
    if d004.get("found") and d004.get("location") == "New York Office":
        c4_score += 10
        feedback.append("C4a: ASSET-D004 created at NYC (+10)")
    else:
        feedback.append(f"C4a: ASSET-D004 missing or wrong location ({d004.get('location', 'not found')}) (+0)")

    if m004.get("found") and m004.get("location") == "New York Office":
        c4_score += 10
        feedback.append("C4b: ASSET-M004 created at NYC (+10)")
    else:
        feedback.append(f"C4b: ASSET-M004 missing or wrong location ({m004.get('location', 'not found')}) (+0)")
    score += c4_score

    # --- C5: Non-London assets unchanged (15 pts) ---
    non_london_changed = int(result.get("non_london_assets_changed", 0))
    if non_london_changed == 0:
        score += 15
        feedback.append("C5: No non-London assets were modified (+15)")
    else:
        feedback.append(f"C5: {non_london_changed} non-London assets were wrongly changed (+0)")

    # --- C6: No London assets remain (10 pts) ---
    if remaining == 0:
        score += 10
        feedback.append("C6: No assets remain at London Office (+10)")
    else:
        feedback.append(f"C6: {remaining} assets still at London Office (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
