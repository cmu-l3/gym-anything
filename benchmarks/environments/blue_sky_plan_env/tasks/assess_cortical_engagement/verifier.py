#!/usr/bin/env python3
"""
Verifier for assess_cortical_engagement task.

SCORING CRITERIA:
1. File Verification (40 pts)
   - File exists and was created during task
   - File contains 3 distinct measurements
   - Measurements are labeled correctly (Crestal, Mid-body, Apical)
   - Values are physiologically plausible (0.3mm - 5.0mm)

2. VLM Verification (60 pts)
   - Trajectory shows navigation to cross-sectional view
   - Measurement tool usage detected
   - Measurements taken at different depths
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assess_cortical_engagement(traj, env_info, task_info):
    """
    Verify that the agent measured cortical bone thickness and saved the results.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 2. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. File Verification
    output_exists = result_data.get('output_exists', False)
    created_fresh = result_data.get('file_created_during_task', False)
    content = result_data.get('file_content', "")

    measurements = {}
    
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists.")
        
        if created_fresh:
            score += 10
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("File timestamp indicates it wasn't created during task.")

        # Parse content
        # Expected format:
        # Crestal (1mm): [value] mm
        patterns = {
            "Crestal": r"Crestal.*:\s*([\d\.]+)",
            "Mid-body": r"Mid-body.*:\s*([\d\.]+)",
            "Apical": r"Apical.*:\s*([\d\.]+)"
        }
        
        valid_values_count = 0
        plausible_values_count = 0
        
        for label, pattern in patterns.items():
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                try:
                    val = float(match.group(1))
                    measurements[label] = val
                    valid_values_count += 1
                    
                    # Physiological check (0.3mm to 5.0mm)
                    if 0.3 <= val <= 5.0:
                        plausible_values_count += 1
                except ValueError:
                    pass
        
        if valid_values_count == 3:
            score += 10
            feedback_parts.append("All 3 measurements found in file.")
        else:
            feedback_parts.append(f"Found {valid_values_count}/3 measurements.")
            
        if plausible_values_count == 3:
            score += 10
            feedback_parts.append("Values are physiologically plausible.")
        elif valid_values_count > 0:
            feedback_parts.append("Some values seem outside normal physiological range (0.3-5.0mm).")

    else:
        feedback_parts.append("Output file not found.")

    # 4. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying a dental software task in Blue Sky Plan.
    The user is supposed to:
    1. Navigate to a cross-sectional view of a tooth/implant.
    2. Use a measurement ruler tool to measure bone thickness.
    
    Look at the sequence of images.
    1. Do you see the Blue Sky Plan interface?
    2. Do you see a cross-sectional view (a view showing a slice of the jaw bone, usually distinct from the panoramic curve)?
    3. Do you see any measurement lines or ruler tools being used on the bone image?
    4. Do you see measurement values (numbers in mm) appearing on the screen?
    
    Return JSON:
    {
      "bsp_interface_visible": true/false,
      "cross_section_view_visible": true/false,
      "measurement_tool_used": true/false,
      "measurement_values_on_screen": true/false
    }
    """
    
    vlm_res = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        if parsed.get('bsp_interface_visible'): vlm_score += 10
        if parsed.get('cross_section_view_visible'): vlm_score += 20
        if parsed.get('measurement_tool_used'): vlm_score += 20
        if parsed.get('measurement_values_on_screen'): vlm_score += 10
        
        feedback_parts.append(f"VLM Analysis: {parsed}")
    else:
        feedback_parts.append("VLM verification failed.")
    
    score += vlm_score
    
    # 5. Final Determination
    # Pass if file has 3 valid measurements AND VLM confirms tool usage
    # OR if file has plausible values and score is high enough
    
    passed = (valid_values_count == 3 and vlm_score >= 30) or (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }