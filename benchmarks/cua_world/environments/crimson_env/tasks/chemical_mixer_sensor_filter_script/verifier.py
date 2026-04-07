#!/usr/bin/env python3
import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_mixer_sensor_filter_script(traj, env_info, task_info):
    """
    Verify the chemical mixer SMA filter script logic.
    Combines Static Code Analysis (regex AST checks) with VLM trajectory verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_path', "C:\\Users\\Docker\\Desktop\\CrimsonTasks\\sma_filter_result.json")

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(result_path, temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Do-Nothing Check
    project_found = result.get('project_found', False)
    code_found = result.get('code_found', False)
    code_content = result.get('code_content', '')
    
    if not project_found:
        return {"passed": False, "score": 0, "feedback": "FAIL: Crimson project file (.c3) not saved."}
    if not code_found or not code_content.strip():
        return {"passed": False, "score": 0, "feedback": "FAIL: Script code not exported to text file."}

    score = 15 # Baseline points for saving the `.c3` project and exporting the `.txt` code
    feedback_parts = ["Files successfully saved"]
    
    # Static Code Analysis (AST/Regex)
    
    # 1. Buffer Insertion (15 pts)
    # Checks for: Level_Array[Filter_Index] = Raw_Level;
    if re.search(r"Level_Array\s*\[\s*Filter_Index\s*\]\s*=\s*Raw_Level", code_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("Buffer insertion correct")
    else:
        feedback_parts.append("Buffer insertion missing/incorrect")

    # 2. Circular Index Management (20 pts)
    # Checks for increment and modulo/if wrapping
    inc = re.search(r"Filter_Index\s*(\+\+|\+=\s*1|=\s*Filter_Index\s*\+\s*1)", code_content, re.IGNORECASE)
    wrap_if = re.search(r"if\s*\([^)]*Filter_Index\s*(>=|==)\s*10[^)]*\).*?(?:\{.*?|;?\s*)Filter_Index\s*=\s*0", code_content, re.IGNORECASE | re.DOTALL)
    wrap_mod = re.search(r"Filter_Index\s*(%|=.*?Filter_Index\s*%)\s*10", code_content, re.IGNORECASE)
    
    if inc and (wrap_if or wrap_mod):
        score += 20
        feedback_parts.append("Circular index management correct")
    else:
        feedback_parts.append("Circular index management missing/incorrect")

    # 3. Summation Logic (20 pts)
    # Checks for a loop mechanism and accumulating array elements
    has_loop = re.search(r"(for|while)\s*\(", code_content, re.IGNORECASE)
    has_acc = re.search(r"\+=\s*Level_Array\s*\[", code_content, re.IGNORECASE) or \
              re.search(r"=\s*[a-zA-Z0-9_]+\s*\+\s*Level_Array\s*\[", code_content, re.IGNORECASE)
    
    if has_loop and has_acc:
        score += 20
        feedback_parts.append("Array summation logic correct")
    else:
        feedback_parts.append("Array summation logic missing/incorrect")

    # 4. Output Calculation (15 pts)
    # Checks for dividing accumulated sum by 10 and assigning to Filtered_Level
    if re.search(r"Filtered_Level\s*=\s*[a-zA-Z0-9_]+\s*\/\s*10", code_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("Output moving average calculation correct")
    else:
        feedback_parts.append("Output moving average calculation missing/incorrect")

    # VLM Trajectory Verification (15 pts)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final]
            
            prompt = """
            Examine these screenshots of the Red Lion Crimson 3.0 interface.
            Did the user configure the properties of the User Program to execute periodically in the background?
            Specifically, look for the Program's 'Task' setting and 'Tick' setting.
            1. Is the 'Task' set to a Background task (like "Background 1")?
            2. Is the 'Tick' execution rate set to 100?
            
            Return JSON only:
            {
                "background_set": true/false,
                "tick_100_set": true/false
            }
            """
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                b_set = parsed.get('background_set', False)
                t_set = parsed.get('tick_100_set', False)
                
                if b_set and t_set:
                    score += 15
                    feedback_parts.append("VLM Verification: Program execution properties (Background, Tick=100) confirmed")
                else:
                    feedback_parts.append("VLM Verification: Program execution properties not correctly configured")
        except Exception as e:
            logger.warning(f"VLM verification failed to run: {e}")

    # Pass threshold is 70 points
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }