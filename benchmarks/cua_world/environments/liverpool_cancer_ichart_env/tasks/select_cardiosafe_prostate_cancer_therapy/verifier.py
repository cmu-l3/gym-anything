#!/usr/bin/env python3
"""
Verifier for select_cardiosafe_prostate_cancer_therapy.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cardiosafe_therapy_selection(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Checked interactions for both Enzalutamide and Abiraterone.
    2. Correctly identified the interaction colors/severities.
    3. Recommended Abiraterone as the safer choice in the report file.
    4. Actually performed the navigation (VLM check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_rec = metadata.get('expected_recommendation', 'Abiraterone')
    
    score = 0
    max_score = 100
    feedback_parts = []

    # ------------------------------------------------------------------
    # 1. File Based Verification (Content Analysis) - 60 Points Max
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    content = result_data.get('file_content', '')
    content_lower = content.lower()
    
    if not result_data.get('file_exists'):
        feedback_parts.append("Report file not created.")
    else:
        score += 10
        feedback_parts.append("Report file created.")

        # Check for Drug Names (Evidence of scope)
        if "enzalutamide" in content_lower and "abiraterone" in content_lower:
            score += 10
            feedback_parts.append("Both cancer drugs mentioned.")
        else:
            feedback_parts.append("Missing cancer drug names in report.")

        if "apixaban" in content_lower and "simvastatin" in content_lower:
            score += 10
            feedback_parts.append("Both co-medications mentioned.")
        else:
            feedback_parts.append("Missing co-medications in report.")

        # Check for Correct Recommendation
        # Must recommend Abiraterone and NOT Enzalutamide
        rec_correct = False
        if "abiraterone" in content_lower and ("safer" in content_lower or "recommend" in content_lower or "better" in content_lower):
            # Ensure it's not saying "Enzalutamide is safer"
            if not ("enzalutamide is safer" in content_lower or "enzalutamide is better" in content_lower):
                rec_correct = True
        
        if rec_correct:
            score += 30
            feedback_parts.append("Correctly recommended Abiraterone.")
        else:
            feedback_parts.append("Failed to clearly recommend Abiraterone as the safer option.")

    # ------------------------------------------------------------------
    # 2. VLM Trajectory Verification - 40 Points Max
    # ------------------------------------------------------------------
    # We need to verify the agent actually navigated to the pages
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's workflow in a medical app "Cancer iChart".
    The task was to check interactions for two cancer drugs: Enzalutamide and Abiraterone.
    
    Look at the sequence of screenshots.
    1. Did the agent search for or select "Enzalutamide"?
    2. Did the agent search for or select "Abiraterone"?
    3. Did the agent view interaction result screens (showing traffic light colors)?
    
    Answer JSON:
    {
        "checked_enzalutamide": true/false,
        "checked_abiraterone": true/false,
        "viewed_results": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('checked_enzalutamide'):
        score += 10
        feedback_parts.append("VLM confirmed Enzalutamide check.")
    else:
        feedback_parts.append("VLM could not confirm Enzalutamide check.")
        
    if vlm_data.get('checked_abiraterone'):
        score += 10
        feedback_parts.append("VLM confirmed Abiraterone check.")
    else:
        feedback_parts.append("VLM could not confirm Abiraterone check.")

    if vlm_data.get('viewed_results'):
        score += 20
        feedback_parts.append("VLM confirmed result viewing.")
    else:
        feedback_parts.append("VLM did not see interaction results.")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 70 and rec_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }