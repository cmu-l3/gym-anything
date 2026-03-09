#!/usr/bin/env python3
"""
Verifier for edit_visitor_record task.

Verification Logic:
1.  **Evidence Check (20 pts):** Did the agent save a screenshot to the correct path?
2.  **VLM Visual Verification (80 pts):**
    - Does the evidence screenshot (or final state) show the visitor "Maria Vasquez"?
    - Is the Company field corrected to "Prestige Global Consulting"?
    - Is the Phone field corrected to "617-443-2810"?
    - Did the agent perform edit actions (trajectory check)?
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the environment framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n=5): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_visitor_record(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_company = metadata.get('expected_company', "Prestige Global Consulting")
    expected_phone = metadata.get('expected_phone', "617-443-2810")
    visitor_name = metadata.get('target_visitor_name', "Maria Vasquez")

    # Load export result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Evidence File Check (20 points)
    agent_screenshot_valid = result.get('agent_screenshot_valid', False)
    if agent_screenshot_valid:
        score += 20
        feedback_parts.append("Evidence screenshot saved correctly.")
    else:
        feedback_parts.append("Evidence screenshot missing or not created during task.")

    # 2. VLM Verification
    # We prioritize the agent's screenshot if valid, otherwise fallback to final system screenshot
    image_to_verify = None
    
    if agent_screenshot_valid:
        # We need to copy the agent's screenshot from the container
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/agent_evidence.png", temp_img.name)
            image_to_verify = temp_img.name
        except Exception:
            logger.warning("Could not retrieve agent evidence image despite valid flag.")
    
    if not image_to_verify:
        # Fallback to trajectory final screenshot
        image_to_verify = get_final_screenshot(traj)

    if not image_to_verify:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No visual evidence available for verification."
        }

    # Construct VLM Prompt
    prompt = f"""
    You are verifying a data entry correction task in a software application.
    
    Target Visitor: {visitor_name}
    Expected Company: {expected_company}
    Expected Phone: {expected_phone}
    
    Please examine the image and answer:
    1. Is a visitor record for "{visitor_name}" visible?
    2. Does the "Company" field show "{expected_company}"?
    3. Does the "Phone" field show "{expected_phone}"?
    4. Does the "Company" field still show the old value "Prestige Worldwide Inc"?
    
    Respond in JSON:
    {{
        "visitor_visible": boolean,
        "company_correct": boolean,
        "phone_correct": boolean,
        "company_is_old_value": boolean,
        "text_seen": "brief summary of text seen in company/phone fields"
    }}
    """
    
    vlm_resp = query_vlm(images=[image_to_verify], prompt=prompt)
    
    if vlm_resp.get("success"):
        parsed = vlm_resp.get("parsed", {})
        
        # Scoring Logic
        if parsed.get("visitor_visible"):
            score += 10
            feedback_parts.append(f"Visitor {visitor_name} record found.")
        else:
            feedback_parts.append(f"Visitor {visitor_name} record NOT visible.")
            
        if parsed.get("company_correct"):
            score += 35
            feedback_parts.append(f"Company correctly updated to {expected_company}.")
        elif parsed.get("company_is_old_value"):
            feedback_parts.append("Company field still shows the OLD incorrect value.")
        else:
            feedback_parts.append(f"Company field incorrect. (Seen: {parsed.get('text_seen')})")
            
        if parsed.get("phone_correct"):
            score += 35
            feedback_parts.append(f"Phone correctly updated to {expected_phone}.")
        else:
            feedback_parts.append("Phone field incorrect.")
    else:
        feedback_parts.append("Visual verification failed (technical error).")

    # 3. Trajectory Sanity Check (Bonus/Penalty)
    # Check if we saw the 'Edit' action or typing
    frames = sample_trajectory_frames(traj, n=5)
    traj_prompt = "Does the user appear to be editing a form in these frames? Are they typing or clicking 'Edit'?"
    traj_resp = query_vlm(images=frames, prompt=traj_prompt)
    
    # We use this mainly for feedback or tie-breaking near threshold, 
    # but strictly the final state matters most for data entry. 
    # If final state is perfect, we assume they edited it.
    
    passed = score >= 90  # Strict threshold because data accuracy is binary
    
    # Cleanup
    if image_to_verify and os.path.exists(image_to_verify) and "tmp" in image_to_verify:
        try:
            os.unlink(image_to_verify)
        except:
            pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }