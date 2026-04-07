#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_patient_allergy(traj, env_info, task_info):
    """
    Verify that the agent correctly recorded a penicillin allergy for the patient.
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Read result file from container
    # ================================================================
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
    
    newly_created = result.get('newly_created', False)
    allergy_type = result.get('allergy_type', '')
    severity = result.get('severity', '')
    pathology_code = result.get('pathology_code', '')
    pathology_name = result.get('pathology_name', '')
    
    # 1. New allergy record exists (30 points) - ANTI-GAMING
    if newly_created:
        score += 30
        feedback_parts.append("New allergy record created")
    else:
        feedback_parts.append("No new allergy record found")
        # Early exit, task not completed
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Correct allergy type (20 points)
    if allergy_type == 'da':
        score += 20
        feedback_parts.append("Correct allergy type (Drug Allergy)")
    else:
        feedback_parts.append(f"Incorrect allergy type: '{allergy_type}' (Expected Drug Allergy)")

    # 3. Correct severity (15 points)
    if severity == '3_sv':
        score += 15
        feedback_parts.append("Correct severity (Severe)")
    else:
        feedback_parts.append(f"Incorrect severity: '{severity}' (Expected Severe)")

    # 4. Correct pathology (20 points)
    if 'Z88.0' in pathology_code or 'penicillin' in pathology_name.lower() or 'penicillin' in pathology_code.lower():
        score += 20
        feedback_parts.append("Correct pathology linked (Penicillin allergy)")
    else:
        feedback_parts.append(f"Incorrect pathology linked: '{pathology_code}' - '{pathology_name}'")

    # 5. VLM trajectory verification (15 points)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and images:
            prompt = (
                "You are evaluating an agent performing a hospital software task. "
                "Did the agent successfully navigate to the patient's Diseases/Conditions section "
                "and create a new allergy record for a Penicillin drug allergy? "
                "Look for evidence of allergy form fields (Allergy Type, Severity, Pathology) being filled. "
                "Answer ONLY 'yes' if there is visual evidence of this process or completion, otherwise 'no'."
            )
            vlm_res = query_vlm(images=images, prompt=prompt)
            if 'yes' in vlm_res.lower():
                score += 15
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM visual verification failed")
        else:
            score += 15
            feedback_parts.append("VLM not available, granting full visual points")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        score += 15
        feedback_parts.append("VLM error, granting full visual points")

    passed = score >= 50 and newly_created and allergy_type == 'da'
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }