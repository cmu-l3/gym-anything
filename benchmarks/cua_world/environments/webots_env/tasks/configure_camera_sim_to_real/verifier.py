#!/usr/bin/env python3
"""
Verifier for configure_camera_sim_to_real task.

Scores based on modifying a Camera node in Webots with proper hardware imperfections:
- Noise and Motion Blur
- Adding and configuring a Lens node
- Adding and configuring a Focus node
- Multi-signal VLM checks via trajectory frames.
"""

import json
import os
import re
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_camera_sim_to_real(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available. Framework error."}

    # 1. Fetch JSON Export
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /home/ga/Desktop/sim_to_real_camera.wbt not found. The world was not saved."
        }

    score = 0
    feedback = []

    if file_modified:
        score += 10
        feedback.append("File created/saved during task (+10)")
    else:
        feedback.append("File was saved BEFORE the task began (Anti-gaming check failed).")

    # 2. Extract and parse the generated .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_content = ""
    try:
        copy_from_env("/home/ga/Desktop/sim_to_real_camera.wbt", wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not read .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # 3. Perform Field Evaluations using Regex

    # Sensor Noise Check
    noise_match = re.search(r'noise\s+([\d.]+)', wbt_content)
    if noise_match and abs(float(noise_match.group(1)) - 0.05) < 0.001:
        score += 10
        feedback.append("Sensor noise set correctly (+10)")
    else:
        feedback.append("Sensor noise incorrect or missing.")

    # Motion Blur Check
    blur_match = re.search(r'motionBlur\s+([\d.]+)', wbt_content)
    if blur_match and abs(float(blur_match.group(1)) - 20.0) < 0.1:
        score += 10
        feedback.append("Motion blur set correctly (+10)")
    else:
        feedback.append("Motion blur incorrect or missing.")

    # Lens Node & Distortion Check
    if 'Lens {' in wbt_content:
        score += 10
        feedback.append("Lens node present (+10)")
        
        radial_match = re.search(r'radialCoefficients\s*\[(.*?)\]', wbt_content)
        if radial_match:
            try:
                # Handle Webots whitespace-based list formats
                floats_str = radial_match.group(1).replace(',', ' ').split()
                floats = [float(x) for x in floats_str if x.strip()]
                if len(floats) >= 2 and abs(floats[0] - (-0.3)) < 0.01 and abs(floats[1] - 0.05) < 0.01:
                    score += 10
                    feedback.append("Lens radialCoefficients set correctly (+10)")
                else:
                    feedback.append(f"Lens radialCoefficients incorrect: found {floats}.")
            except ValueError:
                feedback.append("Could not parse Lens radialCoefficients.")
        else:
            feedback.append("Lens radialCoefficients missing.")
    else:
        feedback.append("Lens node missing.")

    # Focus Node & Parameters Check
    if 'Focus {' in wbt_content:
        score += 10
        feedback.append("Focus node present (+10)")
        
        dist_match = re.search(r'focalDistance\s+([\d.]+)', wbt_content)
        len_match = re.search(r'focalLength\s+([\d.]+)', wbt_content)
        
        dist_correct = dist_match and abs(float(dist_match.group(1)) - 1.2) < 0.01
        len_correct = len_match and abs(float(len_match.group(1)) - 0.02) < 0.001
        
        if dist_correct and len_correct:
            score += 10
            feedback.append("Focus focalDistance and focalLength set correctly (+10)")
        else:
            found_dist = dist_match.group(1) if dist_match else 'none'
            found_len = len_match.group(1) if len_match else 'none'
            feedback.append(f"Focus parameters incorrect (Distance: {found_dist}, Length: {found_len}).")
    else:
        feedback.append("Focus node missing.")

    # 4. Trajectory Verification via VLM (Preventing raw text injection gaming)
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = (
                    "You are verifying a robotics simulation trajectory. The user must modify a 'Camera' node via the GUI.\n"
                    "Review these frames. Did the user expand the Webots Scene Tree and actively interact with the Node properties panel "
                    "(e.g., editing fields or using the 'Add node' dialogue)?\n"
                    "Reply strictly in JSON: {\"scene_tree_interacted\": true/false}"
                )
                vlm_resp = query_vlm(images=images, prompt=prompt)
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("scene_tree_interacted", False):
                    score += 30
                    feedback.append("VLM visual verification confirmed scene tree GUI usage (+30)")
                else:
                    feedback.append("VLM did not confidently detect scene tree interaction.")
            else:
                feedback.append("No frames available for VLM verification.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback.append("VLM trajectory check skipped due to error.")
    else:
        # Fallback if VLM lacks access: reward perfect programmatic success
        if score >= 70:
            score += 30
            feedback.append("VLM unavailable. Auto-awarding trajectory points for perfect config (+30)")

    # 5. Final Calculation
    key_criteria_met = file_modified and ('Lens {' in wbt_content) and ('Focus {' in wbt_content)
    passed = score >= 75 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }