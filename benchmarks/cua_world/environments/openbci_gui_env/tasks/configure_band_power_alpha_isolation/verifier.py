#!/usr/bin/env python3
"""
Verifier for configure_band_power_alpha_isolation@1

This task requires the agent to:
1. Start a synthetic session.
2. Add the Band Power widget.
3. Configure it to ONLY show the Alpha band (hiding Delta, Theta, Beta, Gamma).

Verification relies primarily on VLM analysis of the final screenshot,
as the internal widget state is not easily queryable via files/API.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_band_power_alpha(traj, env_info, task_info):
    """
    Verify the Band Power widget is present and displaying only Alpha.
    """
    # 1. Setup feedback and score
    score = 0
    feedback_parts = []
    max_score = 100
    
    # 2. Check basics (App running, timestamp) from result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result_data.get("app_running"):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was not running at the end.")

    # 3. VLM Verification
    # We need to check if the session is active, widget is there, and bands are correct.
    
    final_img = get_final_screenshot(traj)
    if not final_img:
        return {"passed": False, "score": score, "feedback": "No final screenshot available for analysis."}

    prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    
    Check for the following strictly:
    1. Is a session currently ACTIVE (streaming data, Stop Session button visible)?
    2. Is the 'Band Power' widget visible on the dashboard? (Look for a bar chart labeled Band Power or similar).
    3. In the Band Power widget, which frequency bands are visible?
       - The standard bands are: Delta, Theta, Alpha, Beta, Gamma.
       - The task requires ONLY 'Alpha' to be visible.
       - Are Delta, Theta, Beta, and Gamma hidden/missing from the chart?
    
    Provide a JSON response:
    {
        "session_active": boolean,
        "band_power_widget_present": boolean,
        "only_alpha_visible": boolean,
        "visible_bands": ["list", "of", "bands", "seen"],
        "reasoning": "string explanation"
    }
    """

    try:
        vlm_resp = query_vlm(
            prompt=prompt,
            images=[final_img],
            model="gpt-4o" # or equivalent high-capability vision model
        )
        
        # Parse VLM response (assuming the framework handles JSON parsing from the VLM output)
        # If query_vlm returns a raw string, we might need to parse it. 
        # Assuming query_vlm returns a dict or object with parsed content if verification mode.
        # Adjusting to standard gym_anything pattern where it likely returns a structured dict if requested or we parse.
        
        # Robust parsing fallback
        if isinstance(vlm_resp, str):
            # Try to extract JSON block
            import re
            json_match = re.search(r'\{.*\}', vlm_resp, re.DOTALL)
            if json_match:
                analysis = json.loads(json_match.group(0))
            else:
                analysis = {}
        elif isinstance(vlm_resp, dict) and "parsed" in vlm_resp:
             analysis = vlm_resp["parsed"]
        else:
             analysis = vlm_resp # Hope it's the dict

        # Evaluate VLM findings
        if analysis.get("session_active"):
            score += 20
            feedback_parts.append("Session is active.")
        else:
            feedback_parts.append("Session does not appear active.")

        if analysis.get("band_power_widget_present"):
            score += 30
            feedback_parts.append("Band Power widget found.")
            
            # Only check bands if widget is there
            if analysis.get("only_alpha_visible"):
                score += 40
                feedback_parts.append("SUCCESS: Only Alpha band is visible.")
            else:
                visible = analysis.get("visible_bands", [])
                feedback_parts.append(f"Incorrect bands configuration. Visible: {visible}. Expected only Alpha.")
        else:
            feedback_parts.append("Band Power widget NOT found on dashboard.")

    except Exception as e:
        logger.error(f"VLM Analysis failed: {e}")
        feedback_parts.append(f"Verification error: {str(e)}")

    # 4. Final Verdict
    passed = (score >= 90) # Requires app running, session active, widget present, and correct config
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }