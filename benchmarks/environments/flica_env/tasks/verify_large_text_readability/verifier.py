#!/usr/bin/env python3
"""
Verifier for verify_large_text_readability task.

Criteria:
1. System Font Scale must be significantly > 1.0 (approx 1.15 or 1.3 depending on 'Largest').
2. Agent must have created the requested evidence screenshot (`large_text_test.png`).
3. Agent must have created the text report (`readability_result.txt`).
4. VLM Verification:
   - Verify the evidence screenshot actually shows the specific app (Flight Crew View).
   - Verify the font size in the screenshot appears large.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_large_text_readability(traj, env_info, task_info):
    """
    Verify that the agent increased system font size and documented the result in the app.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Data from Environment
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_evidence = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    result_data = {}
    evidence_path = None
    
    try:
        # Get JSON result
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get Evidence Screenshot (if it exists)
        if result_data.get('screenshot_exists'):
            try:
                copy_from_env("/sdcard/large_text_test.png", temp_evidence.name)
                evidence_path = temp_evidence.name
            except Exception as e:
                logger.warning(f"Could not copy evidence screenshot: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Programmatic Checks (60 Points)
    # ================================================================
    score = 0
    feedback_parts = []
    
    # Check 1: Font Scale (40 pts)
    # Default is usually 1.0. "Largest" is often 1.3 or 1.35. "Large" might be 1.15.
    # We accept anything > 1.1 as evidence of change.
    try:
        font_scale = float(result_data.get('final_font_scale', '1.0'))
        if font_scale >= 1.25:
            score += 40
            feedback_parts.append(f"Font scale set to Largest ({font_scale})")
        elif font_scale > 1.05:
            score += 20
            feedback_parts.append(f"Font scale increased ({font_scale}), but maybe not Largest")
        else:
            feedback_parts.append(f"Font scale unchanged ({font_scale})")
    except ValueError:
        feedback_parts.append("Invalid font scale value returned")

    # Check 2: Evidence Files (20 pts)
    if result_data.get('screenshot_exists') and result_data.get('screenshot_created_during_task'):
        score += 10
        feedback_parts.append("Evidence screenshot created")
    else:
        feedback_parts.append("Missing evidence screenshot")

    if result_data.get('report_exists'):
        content = result_data.get('report_content', '').upper()
        if "READABLE:" in content:
            score += 10
            feedback_parts.append("Report file valid")
        else:
            score += 5
            feedback_parts.append("Report file exists but malformed")
    else:
        feedback_parts.append("Missing report file")

    # ================================================================
    # 3. VLM Verification (40 Points)
    # ================================================================
    # We use the AGENT'S evidence screenshot for verification if available,
    # otherwise fall back to the final frame.
    image_to_verify = evidence_path if evidence_path else get_final_screenshot(traj)
    
    if image_to_verify and os.path.getsize(image_to_verify) > 0:
        vlm_prompt = """
        You are verifying a software testing task.
        The user was asked to set the Android system font size to 'Largest' and then take a screenshot of the 'Flight Crew View' app.
        
        Look at this image and answer:
        1. Is this the 'Flight Crew View' app? (Look for flight lists, 'Friends', or aviation terminology).
        2. Does the text appear significantly larger than standard phone text? (Look for large headers or text taking up much vertical space).
        3. Is the interface 'broken' (text overlapping significantly) or readable?
        
        Return JSON:
        {
            "is_target_app": true/false,
            "text_is_large": true/false,
            "readability": "good/bad",
            "confidence": "high/medium/low"
        }
        """
        
        vlm_result = query_vlm(prompt=vlm_prompt, image=image_to_verify)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("is_target_app"):
                score += 20
                feedback_parts.append("VLM confirmed target app")
            else:
                feedback_parts.append("VLM did not recognize app")
                
            if parsed.get("text_is_large"):
                score += 20
                feedback_parts.append("VLM confirmed large text")
            else:
                feedback_parts.append("VLM did not detect large text")
        else:
            feedback_parts.append("VLM verification failed to run")
    else:
        feedback_parts.append("No valid image for VLM verification")

    # Cleanup evidence file
    if evidence_path and os.path.exists(evidence_path):
        os.unlink(evidence_path)

    # ================================================================
    # 4. Final Scoring
    # ================================================================
    # Pass threshold: 70 points.
    # Must have changed font scale (programmatic) AND provided visual evidence (file existence or VLM)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }