#!/usr/bin/env python3
"""
Verifier for link_patient_family task.

Verification Criteria:
1. Database Record (50 pts): A link exists between the two specific demographic IDs.
2. Relationship Type (20 pts): The relationship is correctly identified as 'Mother' or 'Parent'.
3. Recent Activity (10 pts): The patient record or link was updated today (anti-gaming).
4. VLM Verification (20 pts): Trajectory shows the agent navigating the relationship UI.

"""

import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for trajectory analysis
VLM_PROMPT = """
You are verifying an agent performing a task in an Electronic Medical Record (EMR) system.
The task is to link a child patient (Leo) to his mother (Priya).

Review the screenshot trajectory. Look for:
1. Searching for a patient.
2. Accessing a "Master Demographic" or "Edit Demographic" screen.
3. Using a "Relationship" or "Family Link" section.
4. Selecting "Mother" or "Parent" from a dropdown.

Did the agent perform the necessary steps to link the patients?
Respond with JSON:
{
  "search_performed": true/false,
  "accessed_demographic_edit": true/false,
  "relationship_ui_visible": true/false,
  "confidence": "high/medium/low"
}
"""

def verify_link_patient_family(traj, env_info, task_info):
    """
    Verifies that the family link was created correctly in the database.
    """
    # 1. Setup - Get Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Database Verification (Primary)
    link_found = result.get('link_found', False)
    relation_type = result.get('relation_type', '').lower()
    record_updated = result.get('record_updated_today', False)

    if link_found:
        score += 50
        feedback_parts.append("Family link record found in database.")
        
        # Check Relationship Type
        valid_types = ['mother', 'parent', 'mom']
        if any(t in relation_type for t in valid_types):
            score += 20
            feedback_parts.append(f"Relationship type correct: '{relation_type}'.")
        else:
            feedback_parts.append(f"Relationship type '{relation_type}' may be incorrect (expected Mother).")
    else:
        feedback_parts.append("No family link record found.")

    # 3. Anti-Gaming / Activity Check
    if record_updated:
        score += 10
        feedback_parts.append("Patient record was modified today.")
    else:
        feedback_parts.append("No recent modification detected on patient record.")

    # 4. VLM Verification (Secondary - Process)
    # We only call VLM if we have at least partial success or to confirm details
    # Using a simplified VLM check here for the remaining points
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    # Sample frames to check workflow
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        # Safe parsing of VLM result
        vlm_data = {}
        if vlm_res and isinstance(vlm_res, dict):
            # If the VLM returns parsed JSON in 'parsed' field
            vlm_data = vlm_res.get('parsed', {})
        
        # Award points based on VLM findings
        if vlm_data.get('relationship_ui_visible', False) or vlm_data.get('accessed_demographic_edit', False):
            score += 20
            feedback_parts.append("VLM confirmed UI navigation.")
        elif link_found:
            # If link is found but VLM is unsure, give benefit of doubt for UI navigation
            # (Database is ground truth)
            score += 20 
            feedback_parts.append("Database confirms success (VLM skipped/inconclusive).")
    else:
        # Fallback if no frames available but DB is correct
        if link_found:
             score += 20
             feedback_parts.append("Database confirms success (No trajectory frames).")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }