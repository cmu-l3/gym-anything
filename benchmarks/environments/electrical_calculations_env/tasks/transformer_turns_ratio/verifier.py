#!/usr/bin/env python3
"""
Verifier for Transformer Turns Ratio Task.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transformer_turns_ratio(traj, env_info, task_info):
    """
    Verifies the transformer calculation task using:
    1. File Verification: Check /sdcard/transformer_result.txt content and timestamp.
    2. VLM Verification: Check trajectory for app usage and calculator screen.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sec_turns = metadata.get('expected_secondary_turns', 150)
    expected_ratio = metadata.get('expected_ratio', 4)
    tolerance = metadata.get('tolerance', 0.1)

    score = 0
    feedback_parts = []
    
    # =================================================================
    # PART 1: File & Data Verification
    # =================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    json_path = temp_json.name
    temp_json.close()

    try:
        # Copy result JSON
        copy_from_env("/sdcard/task_result.json", json_path)
        with open(json_path, 'r') as f:
            result_data = json.load(f)
        
        # Check if file exists
        if not result_data.get('file_exists', False):
            feedback_parts.append("Result file '/sdcard/transformer_result.txt' not found.")
        else:
            # Check timestamps (Anti-gaming)
            file_mtime = int(result_data.get('file_mtime', 0))
            task_start = int(result_data.get('task_start_time', 0))
            
            if file_mtime > task_start:
                score += 5
                feedback_parts.append("File created during task.")
                
                # Parse Content
                content = result_data.get('file_content', "")
                
                # Check Secondary Turns
                sec_match = re.search(r'secondary_turns\s*=\s*([\d.]+)', content)
                if sec_match:
                    val = float(sec_match.group(1))
                    if abs(val - expected_sec_turns) <= tolerance:
                        score += 35
                        feedback_parts.append(f"Correct secondary_turns ({val}).")
                    else:
                        feedback_parts.append(f"Incorrect secondary_turns: {val} (expected {expected_sec_turns}).")
                else:
                    feedback_parts.append("Missing 'secondary_turns=' in file.")

                # Check Turns Ratio
                ratio_match = re.search(r'turns_ratio\s*=\s*([\d.]+)', content)
                if ratio_match:
                    val = float(ratio_match.group(1))
                    if abs(val - expected_ratio) <= tolerance:
                        score += 35
                        feedback_parts.append(f"Correct turns_ratio ({val}).")
                    else:
                        feedback_parts.append(f"Incorrect turns_ratio: {val} (expected {expected_ratio}).")
                else:
                    feedback_parts.append("Missing 'turns_ratio=' in file.")
                
                # Format bonus
                if sec_match and ratio_match:
                    score += 5
            else:
                feedback_parts.append("File timestamp is invalid (created before task started).")

    except Exception as e:
        feedback_parts.append(f"Error reading result data: {str(e)}")
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)

    # =================================================================
    # PART 2: VLM Verification (Trajectory Analysis)
    # =================================================================
    # We check if the agent actually used the app, rather than just writing the file via shell
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    if final_screen:
        frames.append(final_screen)

    vlm_prompt = """
    Analyze these screenshots from an Android device.
    1. Is the "Electrical Engineering Calculations" app visible in any frame?
    2. Is a "Transformer" calculator screen visible?
    3. Are the specific input values '480', '120', and '600' visible in input fields?
    
    Return JSON:
    {
        "app_seen": boolean,
        "transformer_screen_seen": boolean,
        "inputs_seen": boolean
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed_vlm = vlm_result.get('parsed', {})
        
        if parsed_vlm.get('app_seen', False):
            score += 10
            feedback_parts.append("App usage confirmed.")
        
        if parsed_vlm.get('transformer_screen_seen', False):
            score += 10
            feedback_parts.append("Transformer calculator accessed.")
            
        # Optional: Bonus/confirmation for inputs
        if parsed_vlm.get('inputs_seen', False):
            feedback_parts.append("Correct inputs verified visually.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Don't penalize heavily if VLM fails, but don't award points
        feedback_parts.append("Visual verification unavailable.")

    # =================================================================
    # Final Scoring
    # =================================================================
    passed = score >= 70  # Needs at least one correct calculation and some visual proof or both calcs correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }