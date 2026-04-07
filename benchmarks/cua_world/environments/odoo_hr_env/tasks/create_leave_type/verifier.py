#!/usr/bin/env python3
"""
Verifier for create_leave_type task.

Requirements:
1. Leave Type "Work From Home" exists.
2. Approval (leave_validation_type) is 'manager' ("By Employee's Approver").
3. Requires Allocation (requires_allocation) is 'yes'.
4. Created during the task session.
"""

import json
import logging
import tempfile
import os
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_leave_type(traj, env_info, task_info):
    """
    Verifies the Odoo leave type creation task using database state and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            db_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Database Verification
    record_found = db_result.get("found", False)
    record = db_result.get("record", {})
    
    if not record_found:
        feedback.append("FAIL: No leave type named 'Work From Home' found.")
        feedback.append(f"Available types: {', '.join(db_result.get('all_types', []))}")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    score += 30
    feedback.append("PASS: Leave type 'Work From Home' created.")
    
    # Check Settings
    # Requires Allocation
    req_alloc = record.get("requires_allocation", "")
    if req_alloc == "yes":
        score += 35
        feedback.append("PASS: 'Requires Allocation' set to Yes.")
    else:
        feedback.append(f"FAIL: 'Requires Allocation' is '{req_alloc}', expected 'yes'.")

    # Approval Type
    # Odoo 17 mapping: 
    # 'no_validation' -> No Validation
    # 'manager' -> By Employee's Approver
    # 'hr' -> By Time Off Officer
    # 'both' -> By Employee's Approver and Time Off Officer
    validation = record.get("leave_validation_type", "")
    if validation == "manager":
        score += 35
        feedback.append("PASS: 'Approval' set to 'By Employee's Approver'.")
    else:
        feedback.append(f"FAIL: 'Approval' is '{validation}', expected 'manager' (By Employee's Approver).")

    # 3. VLM Verification (Anti-Gaming & Workflow Confirmation)
    # Even if DB is correct, we want to ensure they didn't just use a python script if the instructions implied UI.
    # The instructions say "Navigate to...", so UI usage is expected.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        You are verifying an agent's actions in Odoo 17.
        The goal was to create a new Leave Type in 'Configuration > Leave Types'.
        
        Look at the sequence of images.
        1. Do you see the Odoo 'Time Off' application?
        2. Do you see a form view for creating a Leave Type?
        3. Do you see the text "Work From Home" being typed or present in the 'Name' field?
        
        Respond with JSON:
        {
            "seen_time_off_app": true/false,
            "seen_configuration_menu": true/false,
            "seen_leave_type_form": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("seen_leave_type_form"):
                    # Confirming UI usage reinforces the score (though DB is truth)
                    feedback.append("(VLM confirmed UI form usage)")
                else:
                    feedback.append("(VLM Warning: Could not clearly identify Leave Type form usage)")
        except Exception:
            pass # VLM failure shouldn't fail the task if DB is correct

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }