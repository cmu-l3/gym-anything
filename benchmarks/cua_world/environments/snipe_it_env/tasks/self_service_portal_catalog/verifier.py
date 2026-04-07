#!/usr/bin/env python3
"""Verifier for self_service_portal_catalog task.

Scoring breakdown (100 points):
  C1: Model "Dell U2723QE Monitor" is requestable (15 pts)
  C2: Model "Logitech MX Master 3S" is requestable (15 pts)
  C3: Model "Apple MacBook Pro 16 M3 Max" is NOT requestable (20 pts)
  C4: All three LOANER-T14 assets are requestable (20 pts)
  C5: All three LOANER-T14 assets are assigned to "IT Helpdesk - Walk-up" (20 pts)
  C6: EXEC-T14 assets remain NOT requestable (no false positives) (10 pts)

Pass Threshold: 80 points. Must include C3 and C4 correctly.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/self_service_portal_result.json"


def verify_self_service_portal_catalog(traj, env_info, task_info):
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

    models = result.get("models", {})
    assets = result.get("assets", {})

    # Tracking essential criteria for passing
    c3_passed = False
    c4_passed = False

    # --- Do-nothing gate ---
    # Initial state: Dell=0, Logi=0, Mac=1, All Assets=0.
    if (int(models.get("dell_monitor", {}).get("requestable", 0)) == 0 and
        int(models.get("logi_mouse", {}).get("requestable", 0)) == 0 and
        int(models.get("macbook_pro", {}).get("requestable", 1)) == 1 and
        int(assets.get("LOANER-T14-01", {}).get("requestable", 0)) == 0):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No models or assets were updated."}

    # --- C1: Dell Monitor Requestable (15 pts) ---
    if int(models.get("dell_monitor", {}).get("requestable", 0)) == 1:
        score += 15
        feedback.append("C1: Dell Monitor is requestable (+15)")
    else:
        feedback.append("C1: Dell Monitor is NOT requestable (+0)")

    # --- C2: Logitech Mouse Requestable (15 pts) ---
    if int(models.get("logi_mouse", {}).get("requestable", 0)) == 1:
        score += 15
        feedback.append("C2: Logitech Mouse is requestable (+15)")
    else:
        feedback.append("C2: Logitech Mouse is NOT requestable (+0)")

    # --- C3: MacBook Pro NOT Requestable (20 pts) ---
    if int(models.get("macbook_pro", {}).get("requestable", 1)) == 0:
        score += 20
        c3_passed = True
        feedback.append("C3: MacBook Pro misconfiguration corrected (not requestable) (+20)")
    else:
        feedback.append("C3: MacBook Pro remains requestable! Expected to be removed (+0)")

    # --- C4: Loaner Assets Requestable (20 pts) ---
    loaner_req_count = 0
    for tag in ["LOANER-T14-01", "LOANER-T14-02", "LOANER-T14-03"]:
        if int(assets.get(tag, {}).get("requestable", 0)) == 1:
            loaner_req_count += 1
            
    if loaner_req_count == 3:
        score += 20
        c4_passed = True
        feedback.append("C4: All 3 LOANER laptops made requestable (+20)")
    elif loaner_req_count > 0:
        partial = int(20 * (loaner_req_count / 3))
        score += partial
        feedback.append(f"C4: {loaner_req_count}/3 LOANER laptops made requestable (+{partial})")
    else:
        feedback.append("C4: No LOANER laptops made requestable (+0)")

    # --- C5: Loaner Assets Location (20 pts) ---
    loaner_loc_count = 0
    for tag in ["LOANER-T14-01", "LOANER-T14-02", "LOANER-T14-03"]:
        if assets.get(tag, {}).get("location", "") == "IT Helpdesk - Walk-up":
            loaner_loc_count += 1
            
    if loaner_loc_count == 3:
        score += 20
        feedback.append("C5: All 3 LOANER laptops moved to IT Helpdesk (+20)")
    elif loaner_loc_count > 0:
        partial = int(20 * (loaner_loc_count / 3))
        score += partial
        feedback.append(f"C5: {loaner_loc_count}/3 LOANER laptops moved to IT Helpdesk (+{partial})")
    else:
        feedback.append("C5: No LOANER laptops moved to IT Helpdesk (+0)")

    # --- C6: Executive Assets NOT Requestable (10 pts) ---
    exec_req_count = 0
    for tag in ["EXEC-T14-01", "EXEC-T14-02"]:
        if int(assets.get(tag, {}).get("requestable", 0)) == 1:
            exec_req_count += 1
            
    if exec_req_count == 0:
        score += 10
        feedback.append("C6: EXEC laptops correctly left untouched (+10)")
    else:
        feedback.append(f"C6: {exec_req_count} EXEC laptops were incorrectly made requestable (+0)")

    # Overall Pass check
    passed = score >= 80 and c3_passed and c4_passed

    if not passed and score >= 80:
        feedback.append("FAILED: Did not successfully correct MacBook misconfiguration AND make loaners requestable.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }