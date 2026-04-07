#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_asset_quarantine(traj, env_info, task_info):
    """
    Verify that corrupt assets were moved to quarantine and valid assets remain.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Quarantine Directory Creation (10 pts)
    if result.get("quarantine_exists"):
        score += 10
        feedback.append("Quarantine directory created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Quarantine directory '/home/ga/Desktop/Quarantined_Assets' not found."}

    quarantine_files = set(result.get("quarantine_files", []))
    remaining_ownship = set(result.get("remaining_ownship_files", []))
    remaining_other = set(result.get("remaining_other_files", []))
    
    # 2. Check Asset 1: BadShip_v1 (Loose files) (20 pts)
    # Expect: BadShip_v1.x, BadShip_v1.ini, BadShip_v1_diffuse.png in quarantine
    bs_files = ["BadShip_v1.x", "BadShip_v1.ini", "BadShip_v1_diffuse.png"]
    bs_moved = sum(1 for f in bs_files if f in quarantine_files)
    bs_remain = sum(1 for f in bs_files if f in remaining_ownship)
    
    if bs_moved == 3:
        score += 20
        feedback.append("All BadShip_v1 files quarantined.")
    elif bs_moved > 0:
        score += int(20 * (bs_moved / 3))
        feedback.append(f"Partial BadShip_v1 files quarantined ({bs_moved}/3).")
    else:
        feedback.append("BadShip_v1 files NOT quarantined.")

    # 3. Check Asset 2: RustyBuoy (Folder) (20 pts)
    # Expect: RustyBuoy folder in quarantine
    if "RustyBuoy" in quarantine_files:
        score += 20
        feedback.append("RustyBuoy folder quarantined.")
    elif "RustyBuoy" in remaining_other:
        feedback.append("RustyBuoy folder NOT quarantined.")
    else:
        feedback.append("RustyBuoy folder missing from both locations (deleted?).")

    # 4. Check Asset 3: CorruptTankerC (Loose files) (20 pts)
    tc_files = ["CorruptTankerC.x", "CorruptTankerC.ini"]
    tc_moved = sum(1 for f in tc_files if f in quarantine_files)
    
    if tc_moved == 2:
        score += 20
        feedback.append("All CorruptTankerC files quarantined.")
    elif tc_moved > 0:
        score += 10
        feedback.append("Partial CorruptTankerC files quarantined.")
    else:
        feedback.append("CorruptTankerC files NOT quarantined.")

    # 5. Check False Positives (Good assets moved) & Report (20 pts total)
    penalty = 0
    
    # ValidShip should be in remaining_ownship (folder)
    if "ValidShip" in quarantine_files:
        penalty += 10
        feedback.append("Incorrectly quarantined ValidShip!")
    
    # GoodBuoy files should be in remaining_other
    gb_files = ["GoodBuoy.x", "GoodBuoy.ini", "GoodBuoy_Map.png"]
    gb_moved = sum(1 for f in gb_files if f in quarantine_files)
    if gb_moved > 0:
        penalty += 10
        feedback.append(f"Incorrectly quarantined {gb_moved} GoodBuoy files!")

    if penalty == 0:
        score += 10
        feedback.append("No valid assets wrongly removed.")
    else:
        score = max(0, score - penalty)

    # Report check
    if result.get("report_exists"):
        content = result.get("report_content", "").lower()
        if "badship" in content or "rusty" in content or "tanker" in content:
            score += 10
            feedback.append("Report exists and lists assets.")
        else:
            score += 5
            feedback.append("Report exists but content is vague.")
    else:
        feedback.append("Report missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }