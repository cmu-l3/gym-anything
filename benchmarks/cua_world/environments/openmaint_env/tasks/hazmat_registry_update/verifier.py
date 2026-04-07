#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hazmat_registry_update(traj, env_info, task_info):
    """
    Verify hazmat registry update task.
    
    Criteria:
    1. HAZ-001 (Lobby) is retired/inactive (20 pts)
    2. HAZ-002 created in Boiler Room with 'Asbestos' in description (20 pts)
    3. HAZ-003 created in Roof Access with 'Asbestos' in description (20 pts)
    4. NO asset created for Office 102 (Trap) (20 pts)
    5. Warning text added to Boiler Room and Roof Access room records (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Abatement (20 pts)
    haz1 = result.get("haz1", {})
    if haz1.get("retired"):
        score += 20
        feedback.append("HAZ-001 successfully retired.")
    else:
        feedback.append(f"HAZ-001 not retired (Active: {haz1.get('active')}, Status: {haz1.get('status')}).")

    # 2. HAZ-002 Creation (20 pts)
    haz2 = result.get("haz2", {})
    if haz2.get("found"):
        if haz2.get("correct_room"):
            score += 10
            feedback.append("HAZ-002 created in correct room.")
        else:
            feedback.append("HAZ-002 created but in WRONG room.")
            
        if haz2.get("desc_has_asbestos"):
            score += 10
            feedback.append("HAZ-002 has correct description.")
        else:
            feedback.append("HAZ-002 missing 'Asbestos' in description.")
    else:
        feedback.append("HAZ-002 not found.")

    # 3. HAZ-003 Creation (20 pts)
    haz3 = result.get("haz3", {})
    if haz3.get("found"):
        if haz3.get("correct_room"):
            score += 10
            feedback.append("HAZ-003 created in correct room.")
        else:
            feedback.append("HAZ-003 created but in WRONG room.")
            
        if haz3.get("desc_has_asbestos"):
            score += 10
            feedback.append("HAZ-003 has correct description.")
        else:
            feedback.append("HAZ-003 missing 'Asbestos' in description.")
    else:
        feedback.append("HAZ-003 not found.")

    # 4. Trap Avoidance (20 pts)
    if not result.get("trap_triggered"):
        score += 20
        feedback.append("Correctly ignored negative result for Office 102.")
    else:
        feedback.append("FAILED TRAP: Created asset for negative result in Office 102.")

    # 5. Room Warnings (20 pts)
    warnings = result.get("warnings", {})
    w_boiler = warnings.get("boiler", False)
    w_roof = warnings.get("roof", False)
    
    if w_boiler: score += 10
    if w_roof: score += 10
    
    if w_boiler and w_roof:
        feedback.append("Room warnings updated correctly.")
    elif w_boiler or w_roof:
        feedback.append("Room warnings partially updated.")
    else:
        feedback.append("Room warnings missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }