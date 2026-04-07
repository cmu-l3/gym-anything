#!/usr/bin/env python3
"""
Verifier for add_patient_coverage task in FreeMED.

Checks for:
1. Patient Maria Santos has a new coverage record.
2. The record points to the correct Insurance Company (BlueCross BlueShield).
3. The record contains the correct policy and group numbers.
4. VLM verifies that the agent navigated the FreeMED UI to complete the task.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_trajectory_prompt():
    """Build VLM prompt to verify trajectory frames show UI interaction."""
    return """Examine these sequential screenshots from a web browser interacting with an Electronic Medical Record (FreeMED).

Task: The user is adding insurance coverage for a patient.

Check for evidence of the following workflow:
1. Searching for or opening the patient chart (Maria Santos).
2. Navigating to the "Coverages" or "Patient Coverages" module.
3. Interacting with a form to enter insurance details (Policy Number, Group Number, etc.).
4. The presence of the FreeMED application interface throughout.

Did the user perform the necessary UI interactions to add patient coverage? 
Respond in JSON format:
{
    "workflow_completed": true/false,
    "saw_patient_chart": true/false,
    "saw_coverage_form": true/false,
    "confidence": "high/medium/low",
    "observations": "brief summary of what is visible in the frames"
}
"""


def verify_add_patient_coverage(traj, env_info, task_info):
    """
    Verify the coverage was successfully added via DB check and VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_policy = metadata.get('policy_number', 'BCB-2024-78432')
    expected_group = metadata.get('group_number', 'GRP-4401-EAST')
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch DB Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_patient_coverage_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            db_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported DB result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not db_result.get("success", False):
        return {"passed": False, "score": 0, "feedback": f"DB Extraction failed: {db_result.get('error')}"}

    patient_id = db_result.get("patient_id")
    insco_id = db_result.get("insco_id")
    coverages = db_result.get("coverages", [])

    if not patient_id:
        feedback_parts.append("CRITICAL: Patient Maria Santos not found in DB.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if not coverages:
        feedback_parts.append("No coverage records found for patient.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # We found coverage(s). Check them against requirements.
    score += 20
    feedback_parts.append("Found coverage record(s) for patient.")

    correct_insco = False
    correct_policy = False
    correct_group = False
    
    # Check all fields dynamically to handle minor schema name variations
    for cov in coverages:
        # Check Insurer ID Linkage (could be 'insco', 'covinsco', etc.)
        for key, val in cov.items():
            if 'insco' in key.lower() and str(val) == str(insco_id):
                correct_insco = True
                
            # Check Policy Number (as substring to be flexible)
            if isinstance(val, str) and expected_policy.lower() in val.lower():
                correct_policy = True
                
            # Check Group Number
            if isinstance(val, str) and expected_group.lower() in val.lower():
                correct_group = True

    if correct_insco:
        score += 20
        feedback_parts.append("Coverage linked to correct Insurer.")
    else:
        feedback_parts.append("Coverage NOT linked to correct Insurer.")
        
    if correct_policy:
        score += 20
        feedback_parts.append(f"Policy number '{expected_policy}' found.")
    else:
        feedback_parts.append("Expected policy number not found.")
        
    if correct_group:
        score += 15
        feedback_parts.append(f"Group number '{expected_group}' found.")
    else:
        feedback_parts.append("Expected group number not found.")

    # 2. VLM Trajectory Check
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                prompt = build_trajectory_prompt()
                vlm_result = query_vlm(prompt=prompt, images=images)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("workflow_completed", False) and parsed.get("saw_coverage_form", False):
                        score += 25
                        feedback_parts.append("VLM confirmed UI interaction workflow.")
                    else:
                        feedback_parts.append("VLM did NOT confirm proper UI interaction.")
                else:
                    feedback_parts.append("VLM query failed.")
        else:
            feedback_parts.append("No trajectory images available for VLM.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped/errored.")

    passed = score >= 75 and correct_policy
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }