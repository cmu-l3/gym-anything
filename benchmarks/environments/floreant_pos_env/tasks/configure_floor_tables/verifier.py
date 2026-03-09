#!/usr/bin/env python3
"""
Verifier for configure_floor_tables task.

VERIFICATION STRATEGY:
1. Programmatic Check (Database):
   - Verify "Patio" floor exists (20 pts)
   - Verify 4 specific tables exist (15 pts each)
   - Verify tables are assigned to the Patio floor (10 pts)
2. VLM Verification (Trajectory):
   - Verify agent navigated Back Office and interacted with forms (10 pts)

Total: 100 points
Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
from vlm_utils import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_floor_tables(traj, env_info, task_info):
    """
    Verify that the floor and tables were configured correctly in the database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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
    feedback_parts = []
    
    # --- 1. Database Verification ---
    
    # Check Floor
    patio_exists = result.get('patio_floor_exists', False)
    patio_id = result.get('patio_floor_id', -1)
    
    if patio_exists and patio_id != -1:
        score += 20
        feedback_parts.append("Patio floor created (+20)")
    else:
        feedback_parts.append("Patio floor NOT found")

    # Check Tables
    tables_found = result.get('tables_found', {})
    expected_tables = [
        {"number": 20, "capacity": 2},
        {"number": 21, "capacity": 4},
        {"number": 22, "capacity": 6},
        {"number": 23, "capacity": 8}
    ]
    
    tables_correct = 0
    tables_on_floor = 0
    
    for exp in expected_tables:
        t_num = str(exp["number"])
        if t_num in tables_found:
            actual = tables_found[t_num]
            # Check capacity
            if actual.get("capacity") == exp["capacity"]:
                score += 15
                tables_correct += 1
                feedback_parts.append(f"Table {t_num} correct (+15)")
            else:
                feedback_parts.append(f"Table {t_num} wrong capacity (expected {exp['capacity']}, got {actual.get('capacity')})")
            
            # Check floor assignment
            if patio_exists and actual.get("floor_id") == patio_id:
                tables_on_floor += 1
            elif patio_exists:
                feedback_parts.append(f"Table {t_num} not on Patio floor")
        else:
            feedback_parts.append(f"Table {t_num} missing")

    # Bonus for all tables on correct floor
    if tables_on_floor == 4:
        score += 10
        feedback_parts.append("All tables assigned to Patio floor (+10)")
    elif tables_on_floor > 0:
        # Partial credit? Maybe strict is better. Let's stick to strict 10pts for all.
        feedback_parts.append(f"Only {tables_on_floor}/4 tables on Patio floor")

    # --- 2. VLM Verification (Workflow) ---
    # Only verify workflow if database check was partial to confirm effort, 
    # or if fully successful to confirm no gaming (teleportation).
    # Here we give 10 points for evident workflow.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user configuring a Point of Sale system.
        Look for:
        1. The Back Office interface (usually grid of icons or explorer tree on left).
        2. A form for "Shop Floor" or "Floor" configuration.
        3. A form for "Table" configuration (with fields for Number, Capacity).
        
        Did the user navigate to the Back Office and attempt to configure floors or tables?
        Respond with JSON: {"workflow_visible": true/false, "reason": "..."}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_visible"):
                score += 10
                feedback_parts.append("Workflow verified visually (+10)")
            else:
                feedback_parts.append("Workflow verification failed or inconclusive")
        except Exception:
            # Fallback if VLM fails - don't penalize too hard if DB is perfect
            if score >= 80: 
                score += 10 # Assume valid if DB is perfect
                feedback_parts.append("Workflow assumed valid")

    # --- Final Score Calculation ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tables_correct": tables_correct,
            "patio_exists": patio_exists,
            "tables_on_floor": tables_on_floor
        }
    }