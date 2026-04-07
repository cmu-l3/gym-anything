#!/usr/bin/env python3
"""
Verifier for inbound_asset_receiving task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inbound_asset_receiving(traj, env_info, task_info):
    """
    Verifies that the agent correctly processed the packing slip.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_serials = metadata.get('valid_serials', [])
    damaged_serial = metadata.get('damaged_serial', "")
    backorder_serial = metadata.get('backorder_serial', "")

    # Retrieve result file
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

    assets = result.get("assets", {})
    log_info = result.get("rejection_log", {})
    
    score = 0
    feedback = []

    # 1. Check Valid Assets (40 pts)
    # 10 pts per valid asset (3 total in valid list -> wait, there are 3 valid items: 1 laptop, 2 monitors)
    # 40 pts total implies we weight them ~13.3 pts each or round. Let's stick to the table in README: 40 pts.
    # We have 3 items. Let's say 13/13/14 pts.
    
    valid_count = 0
    for s in valid_serials:
        if assets.get(s, {}).get("exists"):
            valid_count += 1
    
    score_valid = 0
    if valid_count == 3:
        score_valid = 40
    else:
        score_valid = int((valid_count / 3) * 40)
    
    score += score_valid
    feedback.append(f"Registered {valid_count}/3 valid assets (+{score_valid} pts).")

    # 2. Check Data Accuracy (20 pts)
    # Check if descriptions are roughly correct (contain manufacturer/model) and codes match pattern
    accuracy_pts = 0
    if valid_count > 0:
        correct_desc = 0
        correct_code = 0
        for s in valid_serials:
            data = assets.get(s, {})
            if not data.get("exists"): continue
            
            desc = (data.get("description") or "").lower()
            code = (data.get("code") or "").upper()
            
            # Simple check: Laptop serial implies 'Latitude', Monitor serial implies 'Dell' or 'Monitor'
            if s == "8H29F2X" and "latitude" in desc: correct_desc += 1
            elif "CN-0Y9N" in s and ("monitor" in desc or "dell" in desc): correct_desc += 1
            
            if code.startswith("AST-REC-"): correct_code += 1

        # Calculate accuracy score proportional to found assets
        # Max 10 for desc, 10 for code
        accuracy_pts = int((correct_desc / 3) * 10) + int((correct_code / 3) * 10)
    
    score += accuracy_pts
    if accuracy_pts > 0:
        feedback.append(f"Data accuracy score: {accuracy_pts}/20.")

    # 3. Check Damaged Item Handling (15 pts)
    # Should NOT exist in DB
    if not assets.get(damaged_serial, {}).get("exists"):
        score += 15
        feedback.append("Correctly excluded damaged item from database (+15 pts).")
    else:
        feedback.append("FAILED: Damaged item was registered in database.")

    # 4. Check Backorder Handling (15 pts)
    # Should NOT exist in DB
    if not assets.get(backorder_serial, {}).get("exists"):
        score += 15
        feedback.append("Correctly excluded backordered item (+15 pts).")
    else:
        feedback.append("FAILED: Backordered/Ghost item was registered.")

    # 5. Rejection Log (10 pts)
    if log_info.get("exists"):
        content = log_info.get("content", "")
        if damaged_serial in content:
            score += 10
            feedback.append("Rejection log created correctly (+10 pts).")
        else:
            score += 5
            feedback.append("Rejection log exists but missing damaged serial (+5 pts).")
    else:
        feedback.append("Rejection log file missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }