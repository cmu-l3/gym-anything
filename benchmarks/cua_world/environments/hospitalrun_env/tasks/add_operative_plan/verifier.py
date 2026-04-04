#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_operative_plan(traj, env_info, task_info):
    """
    Verifies that the agent created an operative plan for patient Ahmed Hassan Ali.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_op = metadata.get('operation_description', 'Laparoscopic Cholecystectomy').lower()
    expected_surgeon = metadata.get('surgeon', 'Dr. Sarah Mitchell').lower()
    expected_complexity = metadata.get('complexity', 'Intermediate').lower()
    expected_status = metadata.get('status', 'Planned').lower()

    # Load result from container
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

    # 1. Check if ANY plan was found for the patient
    plans = result.get('plans_found', [])
    if not plans:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No operative plans found for patient Ahmed Hassan Ali."
        }

    # 2. Score the best matching plan
    best_score = 0
    feedback_details = []
    
    for plan in plans:
        current_score = 0
        current_feedback = []
        
        # Base points for existence linked to correct patient (20 pts)
        current_score += 20
        current_feedback.append("Plan created for correct patient.")

        # Check Operation Description (25 pts)
        op_desc = plan.get('operation', '').lower()
        if 'cholecystectomy' in op_desc:
            current_score += 25
            current_feedback.append("Operation description correct.")
        elif op_desc:
            current_score += 5
            current_feedback.append(f"Operation description mismatch ('{op_desc}').")
        else:
            current_feedback.append("Operation description missing.")

        # Check Surgeon (20 pts)
        surgeon = plan.get('surgeon', '').lower()
        if 'mitchell' in surgeon:
            current_score += 20
            current_feedback.append("Surgeon correct.")
        elif surgeon:
            current_score += 5
            current_feedback.append(f"Surgeon mismatch ('{surgeon}').")

        # Check Status (15 pts)
        status = plan.get('status', '').lower()
        if status == expected_status:
            current_score += 15
            current_feedback.append("Status correct.")
        else:
             current_feedback.append(f"Status mismatch ('{status}').")

        # Check Complexity (10 pts)
        complexity = plan.get('complexity', '').lower()
        if complexity == expected_complexity:
            current_score += 10
            current_feedback.append("Complexity correct.")
            
        # Check Notes/Instructions (10 pts) - loose check
        notes = plan.get('notes', '') + " " + plan.get('instructions', '')
        if len(notes) > 10:
            current_score += 10
            current_feedback.append("Notes/Instructions added.")

        if current_score > best_score:
            best_score = current_score
            feedback_details = current_feedback

    # 3. Final Evaluation
    passed = best_score >= 60
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": " ".join(feedback_details)
    }