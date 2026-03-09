#!/usr/bin/env python3
"""
Verifier for Wolf, Goat, Cabbage Logic Task.
Verifies that the agent navigated to the activity, solved the puzzle,
and captured the required intermediate and final states.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wolf_goat_cabbage_logic(traj, env_info, task_info):
    """
    Verifies the river crossing logic puzzle task.
    
    Scoring Criteria:
    1. Files Created (20 pts): Both screenshots exist and were created during task.
    2. Intermediate State (30 pts): VLM confirms Goat on right, others on left.
    3. Solved State (30 pts): VLM confirms all items on right/success.
    4. Trajectory (20 pts): VLM confirms agent actually played (navigation, boat movement).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    mid_step_path = metadata.get('mid_step_path', '/home/ga/Documents/river_mid_step.png')
    solved_path = metadata.get('solved_path', '/home/ga/Documents/river_solved.png')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (20 pts)
    mid_info = result_data.get('mid_step_file', {})
    solved_info = result_data.get('solved_file', {})
    
    files_score = 0
    if mid_info.get('exists') and mid_info.get('created_during_task'):
        files_score += 10
    if solved_info.get('exists') and solved_info.get('created_during_task'):
        files_score += 10
    
    score += files_score
    feedback_parts.append(f"File check: {files_score}/20 pts")

    # 3. VLM Verification of Intermediate Screenshot (30 pts)
    mid_step_score = 0
    if mid_info.get('exists'):
        temp_mid = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(mid_step_path, temp_mid.name)
            
            prompt = """
            Analyze this screenshot of the 'Wolf, Goat, and Cabbage' river crossing game.
            I need to verify a specific intermediate state:
            1. Is the Goat on the RIGHT bank?
            2. Are the Wolf and Cabbage on the LEFT bank?
            3. Is the Boat on the LEFT bank?
            
            Return JSON: {"goat_right": bool, "others_left": bool, "boat_left": bool}
            """
            
            vlm_res = query_vlm(prompt=prompt, image=temp_mid.name)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('goat_right') and parsed.get('others_left'):
                    mid_step_score = 30
                    feedback_parts.append("Intermediate state verified.")
                else:
                    feedback_parts.append(f"Intermediate state incorrect: {parsed}")
            else:
                feedback_parts.append("VLM failed to analyze intermediate screenshot.")
                
        except Exception as e:
            feedback_parts.append(f"Error copying/analyzing mid file: {e}")
        finally:
            if os.path.exists(temp_mid.name):
                os.unlink(temp_mid.name)
    
    score += mid_step_score

    # 4. VLM Verification of Solved Screenshot (30 pts)
    solved_score = 0
    if solved_info.get('exists'):
        temp_solved = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(solved_path, temp_solved.name)
            
            prompt = """
            Analyze this screenshot of the 'Wolf, Goat, and Cabbage' river crossing game.
            1. Are ALL characters (Wolf, Goat, Cabbage) on the RIGHT bank?
            2. Is there a success message, trophy, or flower indicating completion?
            
            Return JSON: {"all_across": bool, "success_indicator": bool}
            """
            
            vlm_res = query_vlm(prompt=prompt, image=temp_solved.name)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('all_across') or parsed.get('success_indicator'):
                    solved_score = 30
                    feedback_parts.append("Solved state verified.")
                else:
                    feedback_parts.append(f"Solved state incorrect: {parsed}")
            else:
                feedback_parts.append("VLM failed to analyze solved screenshot.")
                
        except Exception as e:
            feedback_parts.append(f"Error copying/analyzing solved file: {e}")
        finally:
            if os.path.exists(temp_solved.name):
                os.unlink(temp_solved.name)
                
    score += solved_score

    # 5. Trajectory Verification (20 pts)
    # Check if the agent actually played the game (navigated + moved boat)
    traj_score = 0
    frames = sample_trajectory_frames(traj, n=5)
    
    if frames:
        prompt = """
        You are verifying an agent playing the GCompris 'Wolf, Goat, Cabbage' game.
        Look at these frames chronologically.
        1. Do you see the GCompris menu navigation?
        2. Do you see the specific river crossing activity interface (boat, water, animals)?
        3. Do you see the boat moving back and forth across the river?
        
        Return JSON: {"activity_visible": bool, "boat_movement": bool, "menu_navigation": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('activity_visible') and (parsed.get('boat_movement') or parsed.get('menu_navigation')):
                traj_score = 20
                feedback_parts.append("Trajectory verifies gameplay.")
            else:
                feedback_parts.append(f"Trajectory analysis doubtful: {parsed}")
        else:
             # Fallback if VLM fails on multiple images, give partial credit if app was running
             if result_data.get('app_running'):
                 traj_score = 10
                 feedback_parts.append("Trajectory VLM failed, but app was running (10 pts).")
    else:
        feedback_parts.append("No trajectory frames available.")
    
    score += traj_score

    # Final tally
    passed = score >= 80  # Requires files + substantial correctness
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }