#!/usr/bin/env python3
"""
Verifier for op_amp_noninverting_gain task.

Verifies:
1. Correct numerical results saved to text file.
2. Anti-gaming (files created during task).
3. VLM verification of screenshot and trajectory to ensure correct app usage.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_op_amp_noninverting_gain(traj, env_info, task_info):
    """
    Verify the Op-Amp Non-Inverting Gain task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gain = metadata.get('expected_gain', 10)
    expected_vout = metadata.get('expected_vout', 5.0)
    tolerance_gain = metadata.get('tolerance_gain', 0.5)
    tolerance_vout = metadata.get('tolerance_vout', 0.3)
    
    score = 0
    feedback_parts = []
    
    # Setup temporary directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_json_path = os.path.join(temp_dir, "task_export.json")
        local_txt_path = os.path.join(temp_dir, "op_amp_results.txt")
        local_png_path = os.path.join(temp_dir, "op_amp_result.png")
        
        # 1. Retrieve JSON Export
        try:
            copy_from_env("/sdcard/tasks/task_export.json", local_json_path)
            with open(local_json_path, 'r') as f:
                export_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task export: {str(e)}"}

        # 2. Retrieve Results Text File
        txt_content = ""
        if export_data.get("results_file_exists"):
            try:
                copy_from_env("/sdcard/tasks/op_amp_results.txt", local_txt_path)
                with open(local_txt_path, 'r') as f:
                    txt_content = f.read()
            except Exception as e:
                feedback_parts.append(f"Error reading result file: {str(e)}")

        # 3. Retrieve Screenshot (optional for local check, mainly for VLM)
        if export_data.get("screenshot_exists"):
            try:
                copy_from_env("/sdcard/tasks/op_amp_result.png", local_png_path)
            except:
                pass

        # --- SCORING CRITERIA ---

        # Criterion 1: Results File Existence & Timestamp (10 pts)
        if export_data.get("results_file_exists") and export_data.get("results_created_during_task"):
            score += 10
            feedback_parts.append("Results file created during task.")
        else:
            feedback_parts.append("Results file missing or stale.")

        # Criterion 2: Correct Gain Value (20 pts)
        gain_match = re.search(r"Gain:\s*([0-9.]+)", txt_content, re.IGNORECASE)
        gain_val = None
        if gain_match:
            try:
                gain_val = float(gain_match.group(1))
                if abs(gain_val - expected_gain) <= tolerance_gain:
                    score += 20
                    feedback_parts.append(f"Gain correct ({gain_val}).")
                else:
                    feedback_parts.append(f"Gain incorrect (got {gain_val}, expected {expected_gain}).")
            except ValueError:
                feedback_parts.append("Could not parse Gain value.")
        else:
            feedback_parts.append("Gain not found in text file.")

        # Criterion 3: Correct Vout Value (20 pts)
        vout_match = re.search(r"Vout:\s*([0-9.]+)", txt_content, re.IGNORECASE)
        vout_val = None
        if vout_match:
            try:
                vout_val = float(vout_match.group(1))
                if abs(vout_val - expected_vout) <= tolerance_vout:
                    score += 20
                    feedback_parts.append(f"Vout correct ({vout_val} V).")
                else:
                    feedback_parts.append(f"Vout incorrect (got {vout_val}, expected {expected_vout}).")
            except ValueError:
                feedback_parts.append("Could not parse Vout value.")
        else:
            feedback_parts.append("Vout not found in text file.")

        # Criterion 4: Physical Consistency Check (5 pts)
        # Prevents just writing random numbers that happen to match one expected value
        if gain_val is not None and vout_val is not None:
            # Vout should be approx Gain * 0.5
            calc_vout = gain_val * 0.5
            if abs(vout_val - calc_vout) <= 0.5:
                score += 5
                feedback_parts.append("Values are consistent.")
            else:
                feedback_parts.append("Values are inconsistent (Vout != Gain * Vin).")

        # Criterion 5: App Running at End (5 pts)
        if export_data.get("app_running_at_end"):
            score += 5
        else:
            feedback_parts.append("App was not running at end.")

        # Criterion 6: VLM Verification (40 pts)
        # Check if the agent actually used the app and the non-inverting calculator
        
        # Gather images: Trajectory frames + Saved screenshot (if exists) + Final screenshot
        images_to_check = sample_trajectory_frames(traj, n=4)
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            images_to_check.append(final_screenshot)
        
        # If the agent saved a screenshot, check that too (it proves they followed instructions to save it)
        if os.path.exists(local_png_path):
            images_to_check.append(local_png_path)

        if not images_to_check:
            feedback_parts.append("No visual evidence available for VLM.")
        else:
            prompt = """
            Verify the user's actions in the 'Electrical Calculations' app.
            
            Look for these specific details in the sequence of images:
            1. Did the user navigate to the 'Op-Amp' or 'Operational Amplifier' section?
            2. Is the 'Non-Inverting Amplifier' configuration selected? (Look for circuit diagram or title).
            3. Are the input values approximately: Vin=0.5, Rf=9000, R1/Rg=1000?
            4. Is the result (Gain=10, Vout=5) visible on the screen?
            
            Return JSON:
            {
              "op_amp_section_visited": true/false,
              "non_inverting_mode_selected": true/false,
              "values_entered_correctly": true/false,
              "result_visible": true/false,
              "confidence": "high/medium/low"
            }
            """
            
            try:
                vlm_res = query_vlm(images=images_to_check, prompt=prompt)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    
                    if parsed.get("op_amp_section_visited"):
                        score += 10
                    else:
                        feedback_parts.append("VLM: Op-Amp section not seen.")
                        
                    if parsed.get("non_inverting_mode_selected"):
                        score += 10
                    else:
                        feedback_parts.append("VLM: Non-Inverting mode not seen.")
                        
                    if parsed.get("values_entered_correctly"):
                        score += 10
                    else:
                        feedback_parts.append("VLM: Input values not verified.")
                        
                    if parsed.get("result_visible"):
                        score += 10
                    else:
                        feedback_parts.append("VLM: Result not visible on screen.")
                else:
                    feedback_parts.append("VLM query failed.")
                    # Fallback partial credit if programmatically correct
                    if score >= 50: 
                        score += 20
                        feedback_parts.append("Fallback VLM points awarded based on text result.")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("VLM verification error.")

    # Final Pass/Fail
    passed = score >= 60 and (score >= 50) # Requires at least valid file + values
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }