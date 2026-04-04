#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_led_resistor_calc(traj, env_info, task_info):
    """
    Verify the LED Resistor Calculation task.
    
    Scoring Criteria:
    1. Agent created the requested screenshot file (15 pts)
    2. Agent screenshot is valid/recent (15 pts)
    3. UI contains correct input values (24, 3.2, 20) (20 pts)
    4. UI contains correct result (~1040) (20 pts)
    5. VLM confirms calculator workflow and correctness (30 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_resistance = metadata.get('expected_resistance', '1040')
    
    # Setup temporary files
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "result.json")
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load Result JSON
        try:
            copy_from_env("/sdcard/tasks/led_resistor_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

        # 2. Check Agent Screenshot (File Existence & Timestamp)
        if result.get('agent_screenshot_exists'):
            score += 15
            feedback_parts.append("Screenshot file created")
            
            if result.get('agent_screenshot_valid_timestamp'):
                score += 15
                feedback_parts.append("Screenshot timestamp valid")
            else:
                feedback_parts.append("Screenshot timestamp invalid (pre-dates task)")
        else:
            feedback_parts.append("No screenshot file found at requested path")

        # 3. Analyze UI Dump (Programmatic Content Verification)
        ui_content = ""
        try:
            copy_from_env(result.get('ui_dump_path'), ui_dump_path)
            with open(ui_dump_path, 'r', encoding='utf-8', errors='ignore') as f:
                ui_content = f.read()
        except Exception:
            logger.warning("Could not copy/read UI dump")

        # Check for inputs and output in UI hierarchy
        inputs_found = 0
        if "24" in ui_content: inputs_found += 1
        if "3.2" in ui_content: inputs_found += 1
        if "20" in ui_content: inputs_found += 1
        
        if inputs_found == 3:
            score += 20
            feedback_parts.append("All input values found in UI")
        elif inputs_found > 0:
            score += 10
            feedback_parts.append(f"Some input values found ({inputs_found}/3)")
        else:
            feedback_parts.append("Input values not detected in UI")

        # Check for result (allow formatting variations like 1.04 k or 1040)
        # Regex for 1040 or 1.04k
        if re.search(r"1040|1\.04\s*[kK]", ui_content):
            score += 20
            feedback_parts.append("Correct resistance result (1040) found in UI")
        else:
            feedback_parts.append("Result (1040) not found in UI text")

        # 4. VLM Verification (Visual Confirmation)
        # Use trajectory to ensure they actually used the app
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots of an Android app interaction.
        The user should be using an 'LED Resistor Calculator'.
        
        Check for:
        1. Is the 'Electrical Calculations' app visible?
        2. Is the specific 'LED Resistor' calculator screen open?
        3. Are the input fields set to: Source=24, LED Voltage=3.2, Current=20?
        4. Is the calculated Result shown as approximately 1040 Ohms?
        
        Return JSON:
        {
            "app_visible": true/false,
            "calculator_screen_correct": true/false,
            "inputs_correct": true/false,
            "result_correct": true/false,
            "explanation": "..."
        }
        """
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_score = 0
            if parsed.get("app_visible"): vlm_score += 5
            if parsed.get("calculator_screen_correct"): vlm_score += 10
            if parsed.get("inputs_correct"): vlm_score += 5
            if parsed.get("result_correct"): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM verification: {parsed.get('explanation', 'Passed')}")
        else:
            feedback_parts.append("VLM verification failed to run")
            # Fallback: if programmatic check passed, give partial VLM points
            if score >= 60:
                score += 10 

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 75
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }