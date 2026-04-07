#!/usr/bin/env python3
"""Verifier for employee_offboarding task.

Scoring breakdown (100 points):
  C1: All assets checked in (20 pts)
  C2: MacBook status is Ready to Deploy (10 pts)
  C3: Monitor status is Out for Repair (15 pts)
  C4: iPhone status is Ready to Deploy (10 pts)
  C5: Cisco Phone status is Ready to Deploy (10 pts)
  C6: Offboarding notes present (15 pts)
  C7: User account deleted (15 pts)
  C8: No collateral damage (5 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/employee_offboarding_result.json"

def verify_employee_offboarding(traj, env_info, task_info):
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
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    sl_ready = str(result.get("sl_ready_id", "0"))
    sl_repair = str(result.get("sl_repair_id", "0"))

    assets = {
        "ASSET-SC01": result.get("SC01", {}),
        "ASSET-SC02": result.get("SC02", {}),
        "ASSET-SC03": result.get("SC03", {}),
        "ASSET-SC04": result.get("SC04", {})
    }

    # Verify how many assets were checked in
    checked_in_count = sum(1 for a in assets.values() if a.get("found") and a.get("is_checked_in"))

    # DO-NOTHING gate check
    if checked_in_count == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets were checked in."}

    # C1: All assets checked in (20 pts)
    if checked_in_count == 4:
        score += 20
        feedback.append("C1: All 4 assets checked in (+20)")
    else:
        pts = checked_in_count * 5
        score += pts
        feedback.append(f"C1: {checked_in_count}/4 assets checked in (+{pts})")

    # C2: MacBook (SC01) status (10 pts)
    if str(assets["ASSET-SC01"].get("status_id", "")) == sl_ready:
        score += 10
        feedback.append("C2: MacBook (SC01) status is Ready to Deploy (+10)")
    else:
        feedback.append("C2: MacBook (SC01) status incorrect (+0)")

    # C3: Monitor (SC02) status (15 pts)
    if str(assets["ASSET-SC02"].get("status_id", "")) == sl_repair:
        score += 15
        feedback.append("C3: Monitor (SC02) status is Out for Repair (+15)")
    else:
        feedback.append("C3: Monitor (SC02) status incorrect (+0)")

    # C4: iPhone (SC03) status (10 pts)
    if str(assets["ASSET-SC03"].get("status_id", "")) == sl_ready:
        score += 10
        feedback.append("C4: iPhone (SC03) status is Ready to Deploy (+10)")
    else:
        feedback.append("C4: iPhone (SC03) status incorrect (+0)")

    # C5: Cisco Phone (SC04) status (10 pts)
    if str(assets["ASSET-SC04"].get("status_id", "")) == sl_ready:
        score += 10
        feedback.append("C5: Cisco Phone (SC04) status is Ready to Deploy (+10)")
    else:
        feedback.append("C5: Cisco Phone (SC04) status incorrect (+0)")

    # C6: Offboarding notes (15 pts)
    notes_count = sum(1 for a in assets.values() if a.get("has_note"))
    if notes_count == 4:
        score += 15
        feedback.append("C6: Offboarding notes present on all assets (+15)")
    elif notes_count > 0:
        pts = int((notes_count / 4) * 15)
        score += pts
        feedback.append(f"C6: Offboarding notes on {notes_count}/4 assets (+{pts})")
    else:
        feedback.append("C6: No offboarding notes found (+0)")

    # C7: User account deleted (15 pts)
    if result.get("sarah_deleted"):
        score += 15
        feedback.append("C7: User Sarah Chen deleted (+15)")
    else:
        feedback.append("C7: User Sarah Chen not deleted (+0)")

    # C8: No collateral damage (5 pts)
    collateral = False
    init_assets = int(result.get("initial_other_asset", 0))
    final_assets = int(result.get("final_other_asset", 0))
    init_users = int(result.get("initial_other_user", 0))
    final_users = int(result.get("final_other_user", 0))

    if init_assets != final_assets:
        collateral = True
        feedback.append(f"C8: Collateral damage! Other assets changed ({init_assets} -> {final_assets})")
    if init_users != final_users:
        collateral = True
        feedback.append(f"C8: Collateral damage! Other users changed ({init_users} -> {final_users})")

    if not collateral:
        score += 5
        feedback.append("C8: No collateral damage (+5)")
    else:
        feedback.append("C8: Collateral damage detected (+0)")

    # Pass condition: must score >= 60 AND have checked in all 4 assets
    passed = (score >= 60) and (checked_in_count == 4)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }