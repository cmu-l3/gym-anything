#!/usr/bin/env python3
"""
Verifier for emergency_evacuation_plan_update task.

Requirements:
1. HQ: Upload 'HQ_Evac_Route.pdf' (30 pts)
2. Warehouse: Upload 'Warehouse_ZoneB_Draft.pdf' (30 pts)
3. Warehouse: Description set to 'Final Evacuation Plan 2026' (20 pts)
4. North Annex: NO uploads (20 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_evacuation_plan_update(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Task error: {result['error']}"}

    buildings = result.get("buildings", {})
    score = 0
    feedback_parts = []

    # 1. HQ Check (30 pts)
    hq_data = buildings.get("Headquarters", {})
    hq_atts = hq_data.get("attachments", [])
    hq_uploaded = False
    for att in hq_atts:
        if "HQ_Evac" in att.get("filename", ""):
            hq_uploaded = True
            break
    
    if hq_uploaded:
        score += 30
        feedback_parts.append("HQ upload confirmed (30 pts)")
    else:
        feedback_parts.append("HQ upload missing")

    # 2. Warehouse Check (30 pts upload + 20 pts description)
    wh_data = buildings.get("Logistics Warehouse", {})
    wh_atts = wh_data.get("attachments", [])
    wh_uploaded = False
    wh_desc_correct = False
    
    for att in wh_atts:
        fname = att.get("filename", "")
        desc = att.get("description", "").lower()
        
        if "Warehouse" in fname or "ZoneB" in fname:
            wh_uploaded = True
            # Check description
            if "final" in desc and "evacuation" in desc and "2026" in desc:
                wh_desc_correct = True
            break
    
    if wh_uploaded:
        score += 30
        feedback_parts.append("Warehouse upload confirmed (30 pts)")
    else:
        feedback_parts.append("Warehouse upload missing")

    if wh_desc_correct:
        score += 20
        feedback_parts.append("Warehouse description correct (20 pts)")
    elif wh_uploaded:
        feedback_parts.append("Warehouse description incorrect (expected 'Final Evacuation Plan 2026')")

    # 3. North Annex Check (20 pts - Negative Constraint)
    na_data = buildings.get("North Annex", {})
    na_count = na_data.get("attachment_count", 0)
    
    if na_count == 0:
        score += 20
        feedback_parts.append("North Annex correctly skipped (20 pts)")
    else:
        feedback_parts.append(f"North Annex wrongly has {na_count} attachment(s)")

    # Anti-gaming: Do nothing check
    # If no attachments found anywhere, ensure score is 0 even if North Annex logic gave points
    total_atts = len(hq_atts) + len(wh_atts) + na_count
    if total_atts == 0:
        score = 0
        feedback_parts = ["DO NOTHING DETECTED: No attachments uploaded anywhere."]

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }