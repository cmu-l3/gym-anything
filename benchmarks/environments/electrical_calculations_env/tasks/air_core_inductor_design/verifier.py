#!/usr/bin/env python3
"""
Verifier for Air Core Inductor Design task.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_air_core_inductor(traj, env_info, task_info):
    """
    Verifies the air core inductor calculation task.
    
    Criteria:
    1. Result file exists and was created during task (20 pts)
    2. Numeric result is within tolerance (40 pts)
    3. VLM: Correct calculator screen reached (20 pts)
    4. VLM: Correct inputs (40, 50, 35) entered (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_inductance_uh', 28.3)
    tolerance = metadata.get('tolerance_uh', 4.5)  # Allow wider range (24-33 roughly)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Result File Existence & Creation Time
    output_exists = result_data.get('output_exists', False)
    created_during_task = result_data.get('created_during_task', False)
    
    if output_exists and created_during_task:
        score += 20
        feedback_parts.append("Result file created successfully.")
    elif output_exists:
        feedback_parts.append("Result file exists but timestamp suggests pre-existence.")
    else:
        feedback_parts.append("Result file not found.")

    # 3. Check Numeric Value
    numeric_pass = False
    if output_exists:
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/sdcard/inductor_result.txt", temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                content = f.read().strip()
                
            # Extract number
            match = re.search(r"([\d\.]+)", content)
            if match:
                val = float(match.group(1))
                diff = abs(val - expected_val)
                if diff <= tolerance:
                    score += 40
                    numeric_pass = True
                    feedback_parts.append(f"Value {val} µH is within tolerance (Expected ~{expected_val}).")
                else:
                    feedback_parts.append(f"Value {val} µH is outside tolerance (Expected ~{expected_val} ±{tolerance}).")
            else:
                feedback_parts.append("Could not parse number from file content.")
        except Exception as e:
            feedback_parts.append(f"Error reading result file: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    # 4. VLM Verification (Trajectory & Final State)
    # Check for inputs: 40, 50, 35 and "Air Core" or "Coil" context
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if not images_to_check:
        feedback_parts.append("No screenshots available for VLM verification.")
    else:
        prompt = """
        Analyze these screens from an electrical calculation app.
        1. Is the user on an "Air Core Inductor" or "Coil" calculator screen?
        2. Do you see the input values "40", "50", and "35" entered in the fields?
        3. Do you see a result calculated?
        
        Return JSON:
        {
            "correct_calculator": true/false,
            "inputs_visible": true/false,
            "result_visible": true/false
        }
        """
        
        try:
            vlm_res = query_vlm(images=images_to_check, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('correct_calculator'):
                score += 20
                feedback_parts.append("VLM: Correct calculator screen identified.")
            else:
                feedback_parts.append("VLM: Could not confirm 'Air Core Inductor' screen.")
                
            if parsed.get('inputs_visible'):
                score += 20
                feedback_parts.append("VLM: Input values (40, 50, 35) confirmed.")
            else:
                feedback_parts.append("VLM: Specific input values not clearly visible.")
                
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {e}")

    # Final Pass Logic
    # Pass if: (Numeric Correct) OR (Inputs Visible AND Correct Calculator AND File Created)
    # This allows passing even if the specific formula used by the app differs slightly, provided work is shown.
    passed = (numeric_pass and score >= 60) or (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }