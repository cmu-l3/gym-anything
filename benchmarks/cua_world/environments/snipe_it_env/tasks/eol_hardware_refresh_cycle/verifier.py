#!/usr/bin/env python3
"""
Verifier for eol_hardware_refresh_cycle task.
Checks completion of a multi-phase hardware refresh workflow involving
state changes, precise assignments, and exclusionary rules.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/task_result.json"

def verify_eol_hardware_refresh_cycle(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    lbl = result.get("status_label", {})
    assets = result.get("assets", {})
    users = result.get("users", {})

    eol_01 = assets.get("eol_01", {})
    eol_02 = assets.get("eol_02", {})
    act_01 = assets.get("act_01", {})
    mon_01 = assets.get("mon_01", {})

    lbl_id = lbl.get("id")

    # Anti-gaming: Do Nothing check
    alice_initially_assigned = eol_01.get("assigned_to") == users.get("alice", {}).get("id")
    bob_initially_assigned = eol_02.get("assigned_to") == users.get("bob", {}).get("id")
    if alice_initially_assigned and bob_initially_assigned and not lbl.get("found"):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets were modified and no label was created."}

    # C1: Status label created as undeployable (10 pts)
    if lbl.get("found"):
        if lbl.get("deployable") == "0" and lbl.get("pending") == "0" and lbl.get("archived") == "0":
            score += 10
            feedback.append("C1: 'Pending E-Waste' label created properly (+10)")
        else:
            feedback.append("C1: Label created but not configured as 'Undeployable' type (+0)")
    else:
        feedback.append("C1: 'Pending E-Waste' label not found (+0)")

    # C2: EOL Reclaimed (20 pts)
    reclaimed_count = 0
    if eol_01.get("assigned_to") in ["0", "NULL", ""]: reclaimed_count += 1
    if eol_02.get("assigned_to") in ["0", "NULL", ""]: reclaimed_count += 1
    
    if reclaimed_count == 2:
        score += 20
        feedback.append("C2: Both EOL laptops successfully reclaimed (+20)")
    elif reclaimed_count == 1:
        score += 10
        feedback.append("C2: Only 1 EOL laptop reclaimed (+10)")
    else:
        feedback.append("C2: EOL laptops were not reclaimed (+0)")

    # C3: EOL Status Updated (15 pts)
    if lbl_id:
        status_count = 0
        if eol_01.get("status_id") == lbl_id: status_count += 1
        if eol_02.get("status_id") == lbl_id: status_count += 1
        
        if status_count == 2:
            score += 15
            feedback.append("C3: EOL laptops status changed to 'Pending E-Waste' (+15)")
        elif status_count == 1:
            score += 7
            feedback.append("C3: Only 1 EOL laptop had status updated (+7)")
        else:
            feedback.append("C3: EOL laptops status not updated (+0)")
    else:
        feedback.append("C3: Cannot verify status update (Label missing) (+0)")

    # C4: Replacements Issued (30 pts)
    alice_assets = users.get("alice", {}).get("assets", [])
    bob_assets = users.get("bob", {}).get("assets", [])
    
    # Check that they have exactly one laptop, and it's NOT the old EOL one
    alice_ok = len(alice_assets) == 1 and "ASSET-EOL" not in alice_assets[0]
    bob_ok = len(bob_assets) == 1 and "ASSET-EOL" not in bob_assets[0]
    
    rep_count = sum([1 for ok in [alice_ok, bob_ok] if ok])
    if rep_count == 2:
        score += 30
        feedback.append("C4: Replacement laptops successfully issued to affected users (+30)")
    elif rep_count == 1:
        score += 15
        feedback.append("C4: Replacement laptop issued to only 1 affected user (+15)")
    else:
        feedback.append("C4: Replacements were not correctly issued (+0)")

    # C5: Date Constraint Valid (15 pts)
    c_charlie_id = users.get("charlie", {}).get("id")
    if act_01.get("assigned_to") == c_charlie_id and act_01.get("status_id") != lbl_id:
        score += 15
        feedback.append("C5: Active laptop correctly ignored based on threshold date (+15)")
    else:
        feedback.append("C5: Active laptop was incorrectly modified (+0)")

    # C6: Category Constraint Valid (10 pts)
    c_dave_id = users.get("dave", {}).get("id")
    if mon_01.get("assigned_to") == c_dave_id and mon_01.get("status_id") != lbl_id:
        score += 10
        feedback.append("C6: Older Monitor correctly ignored based on category (+10)")
    else:
        feedback.append("C6: Monitor was incorrectly modified (+0)")

    passed = score >= 75 and reclaimed_count > 0 and rep_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }