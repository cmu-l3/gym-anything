#!/usr/bin/env python3
"""
Verifier for implement_compliance_login_banner task.
Checks programmatic application state, file modification timestamps, and utilizes VLM to ensure visual UI rendering.
"""

import json
import os
import logging
import tempfile

# Framework imports
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compliance_banner(traj, env_info, task_info):
    """
    Verify the compliance elements were correctly added and rendered.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_warning_text = metadata.get('expected_warning_text', 'UNAUTHORIZED ACCESS IS PROHIBITED. All activity is logged.')
    expected_link_href = metadata.get('expected_link_href', 'https://internal.marketpulse.io/privacy')

    score = 0
    feedback_parts = []

    # 1. Read JSON result from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check HTTP Health (20 points)
    http_code = result.get('http_code', 0)
    if http_code == 200:
        score += 20
        feedback_parts.append("Application loads successfully (HTTP 200)")
    else:
        feedback_parts.append(f"Application failed to load (HTTP {http_code}). PHP syntax error likely.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check anti-gaming: Were files modified during task? (10 points)
    modified_files = result.get('modified_files_count', 0)
    if modified_files > 0:
        score += 10
        feedback_parts.append(f"View files modified ({modified_files} files)")
    else:
        feedback_parts.append("No view files modified during task window")

    # 4. Check Legal Warning DOM Element (15 points for ID, 10 points for Text)
    if result.get('found_warning_id', False):
        score += 15
        feedback_parts.append("Found div with id='legal-warning'")
        
        actual_warning = result.get('warning_text', '')
        if actual_warning == expected_warning_text:
            score += 10
            feedback_parts.append("Warning text matches perfectly")
        elif expected_warning_text.lower() in actual_warning.lower():
            score += 5
            feedback_parts.append("Warning text matched partially")
        else:
            feedback_parts.append(f"Warning text incorrect (Got: '{actual_warning}')")
    else:
        feedback_parts.append("Missing id='legal-warning' element")

    # 5. Check Privacy Link DOM Element (15 points for ID, 10 points for href)
    if result.get('found_link_id', False):
        score += 15
        feedback_parts.append("Found anchor with id='corp-privacy-policy'")
        
        actual_href = result.get('link_href', '')
        if actual_href == expected_link_href:
            score += 10
            feedback_parts.append("Link href matches perfectly")
        else:
            feedback_parts.append(f"Link href incorrect (Got: '{actual_href}')")
    else:
        feedback_parts.append("Missing id='corp-privacy-policy' element")

    # 6. VLM Visual Verification (20 points)
    frames = sample_trajectory_frames(traj, n=3)
    final_image = get_final_screenshot(traj)
    images_to_check = frames + [final_image] if final_image else frames

    if images_to_check:
        prompt = """You are verifying if a user interface modification was successfully rendered in a web browser.
Look at these screenshots. The user was tasked with adding a legal warning banner and a privacy link to the page.

Determine the following:
1. Is the text "UNAUTHORIZED ACCESS IS PROHIBITED. All activity is logged." visibly rendered anywhere on the web page?
2. Is a link or text that says "Privacy Policy" visibly rendered on the web page?

Respond strictly in JSON format:
{
    "warning_visible": true/false,
    "privacy_link_visible": true/false
}
"""
        try:
            vlm_response = query_vlm(images=images_to_check, prompt=prompt)
            if vlm_response and vlm_response.get("success") and vlm_response.get("parsed"):
                parsed = vlm_response["parsed"]
                v_warning = parsed.get("warning_visible", False)
                v_link = parsed.get("privacy_link_visible", False)
                
                if v_warning:
                    score += 10
                    feedback_parts.append("VLM confirmed warning is visible")
                else:
                    feedback_parts.append("VLM could not see the warning text")
                    
                if v_link:
                    score += 10
                    feedback_parts.append("VLM confirmed privacy link is visible")
                else:
                    feedback_parts.append("VLM could not see the privacy link")
            else:
                logger.warning("VLM response failed or parsing error.")
                feedback_parts.append("VLM verification failed to parse")
        except Exception as e:
            logger.error(f"VLM verification exception: {e}")
            feedback_parts.append("VLM verification exception")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }