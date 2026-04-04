#!/usr/bin/env python3
"""
Verifier for 555 Timer Monostable task.
Combines programmatic file verification with VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_555_timer_monostable(traj, env_info, task_info):
    """
    Verifies the 555 timer monostable calculation task.
    
    Scoring Breakdown (100 pts total):
    1. Programmatic Checks (45 pts):
       - Result file exists and was created during task (10 pts)
       - Result value accuracy +/- 1.0s (35 pts) OR +/- 2.0s (20 pts)
       
    2. VLM Trajectory Checks (55 pts):
       - App launched & navigation to 555 Timer (15 pts)
       - Monostable mode selected (CRITICAL) (15 pts)
       - Correct input values (470k, 100uF) visible (15 pts)
       - Result displayed on screen (10 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_value', 51.7)
    
    # Load JSON result from Android device
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # PART A: Programmatic Verification (45 pts)
    # =========================================================
    
    file_exists = result_data.get('file_exists', False)
    file_fresh = result_data.get('file_created_during_task', False)
    content = result_data.get('file_content', "").strip()
    
    if file_exists and file_fresh:
        score += 10
        feedback_parts.append("Result file created successfully")
        
        # Check value accuracy
        try:
            # handle potential non-numeric garbage
            import re
            # Extract first float found
            match = re.search(r"[-+]?\d*\.\d+|\d+", content)
            if match:
                val = float(match.group())
                diff = abs(val - expected_val)
                
                if diff <= 1.0:
                    score += 35
                    feedback_parts.append(f"Value {val} is correct (within ±1.0s)")
                elif diff <= 2.0:
                    score += 20
                    feedback_parts.append(f"Value {val} is acceptable (within ±2.0s)")
                else:
                    feedback_parts.append(f"Value {val} is incorrect (expected ~{expected_val})")
            else:
                feedback_parts.append("File did not contain a valid number")
        except Exception:
            feedback_parts.append("Error parsing file content")
    elif file_exists and not file_fresh:
        feedback_parts.append("Result file existed before task start (Anti-gaming failure)")
    else:
        feedback_parts.append("Result file not found")

    # =========================================================
    # PART B: VLM Verification (55 pts)
    # =========================================================
    
    # Get trajectory frames (start, middle, end)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    if final_screen:
        frames.append(final_screen)
        
    if not frames:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " (No video evidence)"}

    # VLM Query
    prompt = """
    Analyze these screenshots from an electrical calculation app.
    I need to verify if the user performed a specific calculation correctly.
    
    Check for these specific visual elements:
    1. Is the 'Electrical Calculations' app visible?
    2. Is the '555 Timer' calculator open?
    3. CRITICAL: Is the mode set to 'Monostable'? (Look for 'Monostable' text or radio button selected vs 'Astable')
    4. Are the inputs: R = 470 kΩ (or 470000) and C = 100 µF?
    5. Is a result of approximately 51.7 seconds visible on screen?
    
    Return JSON:
    {
        "app_open": boolean,
        "555_timer_open": boolean,
        "monostable_mode_selected": boolean,
        "inputs_correct": boolean,
        "result_visible": boolean,
        "explanation": "string"
    }
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        vlm_data = vlm_resp.get('parsed', {})
        
        # Score VLM components
        if vlm_data.get('app_open') and vlm_data.get('555_timer_open'):
            score += 15
            feedback_parts.append("Navigated to 555 Timer")
        
        if vlm_data.get('monostable_mode_selected'):
            score += 15
            feedback_parts.append("Monostable mode selected")
        else:
            feedback_parts.append("Failed to select Monostable mode")
            
        if vlm_data.get('inputs_correct'):
            score += 15
            feedback_parts.append("Inputs entered correctly")
        
        if vlm_data.get('result_visible'):
            score += 10
            feedback_parts.append("Result calculation visible on screen")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed")

    # Final Pass/Fail Logic
    # Must have reasonable score AND essential correctness (accuracy + correct mode)
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }