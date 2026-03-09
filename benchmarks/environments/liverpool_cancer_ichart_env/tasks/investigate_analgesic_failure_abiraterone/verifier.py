#!/usr/bin/env python3
"""
Verifier for 'Investigate Analgesic Failure with Abiraterone'.
Checks if the agent identified the efficacy issue (CYP2D6 inhibition) with Codeine/Tramadol
and correctly recommended Morphine.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analgesic_investigation(traj, env_info, task_info):
    """
    Verifies the task using:
    1. File Content (Primary): Did the agent write the correct pharmacological analysis?
    2. VLM Trajectory (Secondary): Did the agent actually check the 3 drugs in the app?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["CYP2D6", "efficacy", "metabolite"])
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify File Content (60 points total)
    file_exists = result.get('file_exists', False)
    content = result.get('file_content', "").lower()
    
    if not file_exists:
        feedback_parts.append("Report file not created.")
    else:
        score += 10
        feedback_parts.append("Report file created.")
        
        # Check for mechanism explanation (20 pts)
        # Abiraterone inhibits CYP2D6, preventing conversion of Codeine/Tramadol to active metabolites.
        # Looking for keywords: CYP2D6, efficacy, metabolite, bioactivation, prodrug, reduced effect
        mechanism_found = False
        for kw in required_keywords + ["reduced effect", "reduced efficacy"]:
            if kw.lower() in content:
                mechanism_found = True
                break
        
        if mechanism_found:
            score += 20
            feedback_parts.append("Correctly identified metabolic/efficacy mechanism.")
        else:
            feedback_parts.append("Failed to mention mechanism (CYP2D6/efficacy/metabolite).")

        # Check for correct recommendation (Morphine) vs problematic ones (20 pts)
        rec_morphine = "morphine" in content
        prob_codeine = "codeine" in content
        prob_tramadol = "tramadol" in content
        
        if rec_morphine and prob_codeine:
            score += 20
            feedback_parts.append("Correctly discussed Codeine and recommended Morphine.")
        else:
            feedback_parts.append("Did not clearly identify Codeine failure or Morphine recommendation.")
            
        # Correctness check: Ensure they didn't recommend Tramadol
        # Simple heuristic: if 'tramadol' is close to 'recommend' or 'safe', that's bad.
        # But for now, we'll rely on the overall structure.

    # 3. Verify VLM Trajectory (40 points total)
    # We need to see if they visited the screens for Codeine, Tramadol, and Morphine.
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying a clinical drug interaction check task.
    The user must check interactions for 'Abiraterone' with three specific painkillers: 'Codeine', 'Tramadol', and 'Morphine'.
    
    Look at the sequence of screens.
    1. Did you see the user select 'Abiraterone' as the cancer drug?
    2. Did you see the user check 'Codeine'? (Look for 'Codeine' in the list or result page)
    3. Did you see the user check 'Tramadol'? (Look for 'Tramadol' in the list or result page)
    4. Did you see the user check 'Morphine'? (Look for 'Morphine' in the list or result page)
    
    Return JSON:
    {
        "abiraterone_selected": true/false,
        "checked_codeine": true/false,
        "checked_tramadol": true/false,
        "checked_morphine": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result else {}
    
    if vlm_data.get('abiraterone_selected'):
        score += 10
        feedback_parts.append("VLM: Confirmed Abiraterone selection.")
        
    drugs_checked_count = sum([
        vlm_data.get('checked_codeine', False),
        vlm_data.get('checked_tramadol', False),
        vlm_data.get('checked_morphine', False)
    ])
    
    if drugs_checked_count >= 3:
        score += 30
        feedback_parts.append("VLM: Confirmed checks for all 3 opioids.")
    elif drugs_checked_count >= 1:
        score += 10 * drugs_checked_count
        feedback_parts.append(f"VLM: Confirmed checks for {drugs_checked_count}/3 opioids.")
    else:
        feedback_parts.append("VLM: No opioid checks detected in trajectory.")

    # Final Evaluation
    # Must have created file, mentioned mechanism, and checked at least some drugs
    passed = (file_exists and mechanism_found and rec_morphine and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }