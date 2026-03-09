#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_compliance_analysis(traj, env_info, task_info):
    """
    Verifies that the agent created a Compliance Analysis record in Eramba
    correctly linked to PCI-DSS Req 6.3.3 with the correct status and description.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    import tempfile
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

    # 2. Define Scoring Criteria
    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_keywords = metadata.get('required_keywords', ["30-day SLA", "47 days", "compensating controls"])
    
    # Check 1: Record Created (25 pts)
    record = result.get('record')
    if result.get('record_found') and record:
        score += 25
        feedback_parts.append("Compliance analysis record created.")
        
        # Check 2: Correct Linkage (25 pts)
        item_title = record.get('item_title', '')
        item_id = record.get('item_id', '')
        if '6.3.3' in item_title or '6.3.3' in item_id:
            score += 25
            feedback_parts.append("Correctly linked to Req 6.3.3.")
        else:
            feedback_parts.append(f"Incorrect linkage: Linked to '{item_title}' instead of Req 6.3.3.")

        # Check 3: Description Content (30 pts)
        analysis_text = record.get('analysis_text', '')
        found_keywords = [kw for kw in target_keywords if kw.lower() in analysis_text.lower()]
        
        if len(found_keywords) >= len(target_keywords) - 1: # Allow missing 1 keyword
            score += 30
            feedback_parts.append("Analysis text matches requirements.")
        elif len(found_keywords) > 0:
            partial_score = int(30 * (len(found_keywords) / len(target_keywords)))
            score += partial_score
            feedback_parts.append(f"Analysis text partially matches ({len(found_keywords)}/{len(target_keywords)} keywords).")
        else:
            feedback_parts.append("Analysis text missing or incorrect.")

        # Check 4: Status (10 pts)
        # Eramba status IDs vary, but usually 1=Compliant. 
        # We expect Non-Compliant. We assume if ID != 1 (and != 3 'Not Applicable') it's likely 'Not Compliant' or 'Warning'.
        # Safest check: If status_id is provided, check against known values or VLM fallback.
        # For this verifier, we will assume status_id '1' is Compliant (Success) and anything else is what we want,
        # specifically looking for 'Not Compliant' which is often ID 2 or 3 in default installs.
        # We will award points if it is NOT 'Compliant' (which is the default positive state).
        status_id = record.get('status_id')
        if status_id != 1: # Assuming 1 is Compliant
            score += 10
            feedback_parts.append("Status set to Non-Compliant (or non-default).")
        else:
            feedback_parts.append("Status appears to be Compliant (expected Non-Compliant).")

    else:
        feedback_parts.append("No new compliance analysis record found in database.")

    # Check 5: VLM Verification (10 pts)
    # Use trajectory to verify UI interactions if available
    vlm_score = 0
    try:
        final_screen = get_final_screenshot(traj)
        if final_screen:
            vlm_prompt = """
            Analyze this Eramba screenshot. 
            1. Is the "Compliance Analysis" or "Compliance Management" page visible?
            2. Do you see "Req 6.3.3" or "Patch" listed?
            3. Is there a status indicator showing "Not Compliant", "Fail", or a Red/Orange icon?
            """
            vlm_res = query_vlm(prompt=vlm_prompt, image=final_screen)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {}) # Assuming structure or just checking text
                # Simple text check if structured parse fails
                res_text = vlm_res.get('response', '').lower()
                if "yes" in res_text and ("6.3.3" in res_text or "patch" in res_text):
                    vlm_score = 10
                    feedback_parts.append("Visual verification passed.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final tally
    passed = score >= 65 and result.get('record_found')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }