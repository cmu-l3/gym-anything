#!/usr/bin/env python3
"""
Verifier for cable_ampacity_check task.

Evaluates:
1. Result file existence and valid numeric content.
2. Value accuracy (within reasonable range for 25mm2 Cu PVC in Air).
3. Anti-gaming (file creation time).
4. VLM confirmation of app state and displayed values.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cable_ampacity(traj, env_info, task_info):
    """
    Verify the cable ampacity calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_min', 70.0)
    expected_max = metadata.get('expected_max', 100.0)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Result file /sdcard/ampacity_result.txt not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: Result file timestamp predates task start.")
        # We penalize but don't fail immediately if content is correct, usually implies stiff penalty
        score -= 20
    else:
        score += 10
        feedback_parts.append("File created during task.")

    # 3. Validate Numeric Content
    raw_content = result_data.get("file_content", "").strip()
    try:
        # Handle potential extra text like "89 Amps"
        import re
        numeric_match = re.search(r"(\d+\.?\d*)", raw_content)
        if numeric_match:
            value = float(numeric_match.group(1))
            
            if expected_min <= value <= expected_max:
                score += 40
                feedback_parts.append(f"Value {value}A is within valid range ({expected_min}-{expected_max}A).")
            else:
                feedback_parts.append(f"Value {value}A is outside valid range ({expected_min}-{expected_max}A).")
        else:
            feedback_parts.append(f"Could not parse number from content: '{raw_content}'")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    except Exception:
        feedback_parts.append("Error parsing file content.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. VLM Verification of Screen State
    # We want to ensure they didn't just guess the number (80-90 is common)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = f"""
        You are verifying an electrical calculation task. 
        The user should have calculated Ampacity for:
        - Cable Size: 25 mm² (or similar)
        - Material: Copper
        - Insulation: PVC
        - Installation: Air or Tray
        
        The result file contains the value: {value}
        
        Look at the screenshot and answer:
        1. Is the app showing an "Ampacity" or "Current Carrying Capacity" calculator?
        2. Is the cable size set to 25 mm² (or 25)?
        3. Is the material Copper and Insulation PVC?
        4. Does the result displayed on screen match (or is very close to) {value}?
        
        Return JSON: {{"calculator_correct": bool, "inputs_visible": bool, "value_matches": bool}}
        """
        
        vlm_res = query_vlm(prompt, final_screenshot)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("calculator_correct"):
                score += 20
                feedback_parts.append("Correct calculator screen.")
            else:
                feedback_parts.append("Wrong screen visible.")
                
            if parsed.get("value_matches"):
                score += 30
                feedback_parts.append("Screen value matches file.")
            else:
                feedback_parts.append("Screen value does not match file (possible guessing).")
                
            # Bonus for inputs being visible
            if parsed.get("inputs_visible"):
                feedback_parts.append("Inputs confirmed visually.")
        else:
            feedback_parts.append("VLM verification failed.")
            # Fallback: if value is correct, we give partial credit
            score += 10 

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }