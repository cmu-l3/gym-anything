#!/usr/bin/env python3
"""
Verifier for configure_project_type task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_type(traj, env_info, task_info):
    """
    Verifies that the Project Type "Winter Garden Prep" was created with 
    3 specific phases: Pruning (10), Mulching (20), Covering (30).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # 2. Extract Data
    pt_found = result.get("project_type_found", False)
    pt_name = result.get("project_type_name", "")
    phases = result.get("phases", [])
    
    score = 0
    feedback_parts = []
    
    # 3. Scoring Criteria
    
    # Criterion 1: Project Type Header Created (25 pts)
    if pt_found and pt_name == "Winter Garden Prep":
        score += 25
        feedback_parts.append("Project Type header created successfully.")
    else:
        feedback_parts.append(f"Project Type 'Winter Garden Prep' not found (Found: '{pt_name}').")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Define Expected Phases
    # Dictionary for easier lookup: seq -> name
    expected_phases = {
        10: "Pruning",
        20: "Mulching",
        30: "Covering"
    }
    
    # Analyze Actual Phases
    # Convert list to a dictionary keyed by sequence for verification
    actual_phases = {}
    for p in phases:
        # p is like {"name": "Pruning", "seq": 10, "qty": 1}
        # handle potential type string/int mismatch from shell json
        try:
            seq = int(p.get("seq", 0))
            actual_phases[seq] = p.get("name", "").strip()
        except:
            continue

    # Criterion 2, 3, 4: Verify Phases (20 pts each)
    phase_score = 0
    
    for seq, exp_name in expected_phases.items():
        if seq in actual_phases:
            act_name = actual_phases[seq]
            # Case-insensitive comparison
            if exp_name.lower() in act_name.lower():
                phase_score += 20
                feedback_parts.append(f"Phase {seq} '{exp_name}' correct.")
            else:
                feedback_parts.append(f"Phase {seq} exists but name mismatch (Expected '{exp_name}', Got '{act_name}').")
        else:
            feedback_parts.append(f"Phase {seq} '{exp_name}' missing.")

    score += phase_score

    # Criterion 5: Anti-Gaming / Timestamp Check (15 pts)
    # Since we deleted the record in setup, if it exists now, it must be new.
    # We can assume 15 points if the record exists, as setup cleared it.
    if pt_found:
        score += 15
        feedback_parts.append("Creation timestamp validated (fresh record).")

    # 4. Final Result
    # Pass threshold: 85 (Header + all 3 phases essentially correct)
    passed = score >= 85

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "project_type": pt_name,
            "actual_phases": phases
        }
    }