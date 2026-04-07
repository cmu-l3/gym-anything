#!/usr/bin/env python3
"""Verifier for solar_panel_class_setup task.

Scoring breakdown (100 points total):
  C1 (20 pts): SolarPanel class created and active.
  C2 (25 pts): 5 Custom attributes created with correct types (5 pts each).
  C3 (25 pts): 3 Records created (based on count).
  C4 (15 pts): Record data accuracy (spot check capacity/count).
  C5 (15 pts): Records linked to valid buildings.

Pass threshold: 45 points (Must at least create class and attributes)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_solar_panel_class_setup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    
    score = 0
    feedback_parts = []
    
    # Retrieve result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/sp_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve result: {e}"
        }

    if result.get("error"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Export error: {result['error']}"
        }
        
    class_res = result.get("class_result", {})
    attrs_res = result.get("attributes_result", {})
    records = result.get("records_result", [])
    
    # --- C1: Class Created (20 pts) ---
    if class_res.get("found"):
        score += 20
        feedback_parts.append(f"Class '{class_res['name']}' created (20/20)")
    else:
        feedback_parts.append("SolarPanel class NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- C2: Attributes (25 pts) ---
    attr_score = 0
    missing_attrs = []
    wrong_types = []
    
    for name, info in attrs_res.items():
        if info.get("found"):
            if info.get("type_correct"):
                attr_score += 5
            else:
                attr_score += 2  # Partial for correct name, wrong type
                wrong_types.append(name)
        else:
            missing_attrs.append(name)
            
    score += attr_score
    feedback_parts.append(f"Attributes: {attr_score}/25")
    if missing_attrs:
        feedback_parts.append(f"Missing: {', '.join(missing_attrs)}")
    if wrong_types:
        feedback_parts.append(f"Wrong types: {', '.join(wrong_types)}")

    # --- C3: Records Created (25 pts) ---
    # We expect 3 records
    rec_count = len(records)
    if rec_count >= 3:
        score += 25
        feedback_parts.append("3+ records created (25/25)")
    else:
        rec_pts = int((rec_count / 3.0) * 25)
        score += rec_pts
        feedback_parts.append(f"{rec_count}/3 records found ({rec_pts}/25)")

    # --- C4: Data Accuracy (15 pts) ---
    # Spot check specific values from spec if records exist
    data_ok_count = 0
    for r in records:
        # Check if any attributes populated
        attrs = r.get("attributes", {})
        # Simple heuristic: if Capacity or PanelCount is numeric > 0, give credit
        try:
            cap = float(attrs.get("PanelCapacityKW", 0) or 0)
            count = int(attrs.get("PanelCount", 0) or 0)
            if cap > 0 or count > 0:
                data_ok_count += 1
        except:
            pass
            
    if rec_count > 0:
        data_score = int((data_ok_count / rec_count) * 15)
        score += data_score
        feedback_parts.append(f"Data accuracy: {data_score}/15")
    else:
        feedback_parts.append("No data to verify")

    # --- C5: Building Links (15 pts) ---
    valid_links = result.get("building_links_valid", 0)
    if rec_count > 0:
        link_score = int((valid_links / rec_count) * 15)
        score += link_score
        feedback_parts.append(f"Building links: {link_score}/15")
    else:
        feedback_parts.append("No links to verify")

    # --- Preservation Malus ---
    if not result.get("preservation_ok", True):
        score = min(score, 60)
        feedback_parts.append("PENALTY: Existing classes deleted")

    return {
        "passed": score >= 45,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }