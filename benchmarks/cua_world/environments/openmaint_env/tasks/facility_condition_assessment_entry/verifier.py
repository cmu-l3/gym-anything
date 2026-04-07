#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def verify_facility_condition_assessment_entry(traj, env_info, task_info):
    """
    Verifies that:
    1. All 5 assets were updated with FCA notes.
    2. Work Orders were created for EQ-FCA-001 and EQ-FCA-003.
    3. Work Orders were NOT created for EQ-FCA-002, 004, or 005 (Heritage trap).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    work_orders = result.get("work_orders", [])
    
    score = 0
    feedback = []

    # Criterion 1: Data Entry (25 pts)
    # Check if "FCA 2026: Condition" string is present in all 5 assets
    assets_updated = 0
    for code in ["EQ-FCA-001", "EQ-FCA-002", "EQ-FCA-003", "EQ-FCA-004", "EQ-FCA-005"]:
        asset_data = assets.get(code, {})
        full_text = asset_data.get("full_text", "")
        if "FCA 2026: Condition" in full_text:
            assets_updated += 1
    
    data_entry_score = (assets_updated / 5) * 25
    score += data_entry_score
    feedback.append(f"Data Entry: {assets_updated}/5 assets updated.")

    # Criterion 2: Logic Application (Replacement Requests) (75 pts)
    # Expected: 
    # EQ-FCA-001: WO exists, Priority Critical
    # EQ-FCA-003: WO exists, Priority Critical
    # EQ-FCA-002, 004, 005: NO WO linked
    
    created_wos_map = {wo['linked_asset']: wo for wo in work_orders if wo.get('linked_asset')}
    
    # 2a. Correct WOs Created (25 pts)
    correct_creations = 0
    if "EQ-FCA-001" in created_wos_map: correct_creations += 1
    if "EQ-FCA-003" in created_wos_map: correct_creations += 1
    
    creation_score = (correct_creations / 2) * 25
    score += creation_score
    if correct_creations == 2:
        feedback.append("Correct WOs created for poor condition assets.")
    else:
        feedback.append(f"Missing WOs: Found {correct_creations}/2 expected.")

    # 2b. Heritage Trap (20 pts)
    # EQ-FCA-005 (Score 2, Heritage) should NOT have a WO
    heritage_penalty = 0
    if "EQ-FCA-005" in created_wos_map:
        heritage_penalty = 20
        feedback.append("FAIL: Heritage trap triggered! Created WO for protected asset.")
    else:
        score += 20
        feedback.append("Success: Heritage asset correctly skipped.")

    # 2c. False Positives (15 pts)
    # EQ-FCA-002 (Score 4) and 004 (Score 5) should NOT have WOs
    false_positives = 0
    if "EQ-FCA-002" in created_wos_map: false_positives += 1
    if "EQ-FCA-004" in created_wos_map: false_positives += 1
    
    fp_score = 15
    if false_positives > 0:
        fp_score = 0
        feedback.append(f"FAIL: Created unnecessary WOs for Good/Fair assets ({false_positives}).")
    score += fp_score

    # 2d. Quality Check (15 pts)
    # Check Priority = Critical for the created WOs
    quality_score = 0
    quality_checks = 0
    for code in ["EQ-FCA-001", "EQ-FCA-003"]:
        if code in created_wos_map:
            wo = created_wos_map[code]
            prio = wo.get("priority", "").lower()
            if "critical" in prio or "high" in prio or "urgent" in prio:
                quality_score += 7.5
            quality_checks += 1
            
    score += quality_score
    if quality_checks > 0 and quality_score == 15:
        feedback.append("WO Priorities set correctly.")

    passed = score >= 60 and (correct_creations >= 1) and (heritage_penalty == 0)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }