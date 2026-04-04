#!/usr/bin/env python3
"""
Verifier for analyze_tad_site task in Blue Sky Plan.

Verification Strategy:
1. VLM (Primary): Check trajectory frames to ensure agent visualized roots (X-ray/Transparency/Clipping) and placed a measurement tool.
2. File-based: Check if the report exists and contains valid values.
3. Logic: Check if the reported conclusion (Safe/Risky) matches the measurement (>3mm vs <=3mm).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_tad_site(traj, env_info, task_info):
    """
    Verify TAD site analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve JSON result from Windows container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style, but copy_from_env handles the mapping
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate File Output (30 points)
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    measurement = float(result_data.get('parsed_measurement', 0))
    conclusion = str(result_data.get('parsed_conclusion', "")).strip().lower()

    if output_exists and created_during:
        score += 15
        feedback_parts.append("Report created.")
        
        # Check Logic
        if measurement > 0:
            score += 5
            feedback_parts.append(f"Measurement recorded: {measurement}mm.")
            
            # Check consistency (Safe > 3.0)
            is_safe_val = measurement > 3.0
            is_safe_conc = "safe" in conclusion
            is_risky_conc = "risky" in conclusion
            
            if (is_safe_val and is_safe_conc) or (not is_safe_val and is_risky_conc):
                score += 10
                feedback_parts.append("Conclusion logic is correct.")
            else:
                feedback_parts.append("Conclusion logic mismatch.")
        else:
            feedback_parts.append("No valid measurement value found.")
    else:
        feedback_parts.append("Report file not created or not modified.")

    # 3. VLM Verification (70 points)
    # We look for:
    # A. Root visualization (Transparency/Clipping) - 40 pts
    # B. Measurement line placement - 30 pts
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    if final_shot:
        frames.append(final_shot)

    if not query_vlm:
         feedback_parts.append("VLM verification unavailable.")
    else:
        prompt = """
        You are verifying a dental analysis task. 
        Goal: Visualize the roots of teeth (canine/premolar) inside the bone and measure the distance between them.
        
        Look at the provided screenshots.
        1. Root Visibility: Do you see the ROOTS of the teeth inside the jawbone? This requires the view to be semi-transparent (X-ray style) OR sliced/clipped. If you only see solid white bone surface, answer NO.
        2. Measurement: Is there a measurement line drawn between two adjacent tooth roots?
        
        Return JSON:
        {
          "roots_visible": boolean,
          "measurement_line_visible": boolean,
          "description": "string"
        }
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp and vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            if analysis.get('roots_visible'):
                score += 40
                feedback_parts.append("Roots visualized correctly.")
            else:
                feedback_parts.append("Failed to visualize roots inside bone.")
                
            if analysis.get('measurement_line_visible'):
                score += 30
                feedback_parts.append("Measurement line visible.")
            else:
                feedback_parts.append("No measurement line detected.")
        else:
            feedback_parts.append("VLM analysis failed.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }