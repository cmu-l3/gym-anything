#!/usr/bin/env python3
"""
Verifier for configure_automotive_radar_rcs task.

An ADAS Validation Engineer must reconfigure an ego vehicle's radar (maxRange, 
horizontalFieldOfView, rangeNoise) and a lead vehicle's physical properties 
(radarCrossSection) to enable highway ACC testing.

Scoring (100 points total):
  - File saved correctly and during task: 10 points
  - Radar maxRange = 250.0: 20 points
  - Radar horizontalFieldOfView = 0.314: 20 points
  - Radar rangeNoise = 0.1: 20 points
  - Target radarCrossSection = 100.0: 30 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging
import sys

# Add path for vlm_utils if needed
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)


def verify_configure_automotive_radar_rcs(traj, env_info, task_info):
    """
    Verify that the automotive radar scenario has been correctly configured and saved.
    Extracts parameters from the generated .wbt file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/acc_highway_configured.wbt')
    expected_range = metadata.get('expected_max_range', 250.0)
    expected_fov = metadata.get('expected_fov', 0.314)
    expected_noise = metadata.get('expected_noise', 0.1)
    expected_rcs = metadata.get('expected_rcs', 100.0)

    score = 0
    feedback_parts = []

    # --- Read export metadata ---
    export_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Copy the .wbt file ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file from VM: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # --- Check file existence and anti-gaming ---
    file_exists = export_result.get('file_exists', False)
    if not file_exists or not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Ensure it is saved using File > Save World As."
        }
    
    if not export_result.get('file_created_during_task', True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was not created or modified during the task session. Anti-gaming check failed."
        }

    score += 10
    feedback_parts.append("World file correctly saved")

    # --- Parameter Verification via Regex ---
    
    # 1. maxRange
    range_match = re.search(r'maxRange\s+([\d.]+)', wbt_content)
    if range_match:
        actual_range = float(range_match.group(1))
        if abs(actual_range - expected_range) < 0.1:
            score += 20
            feedback_parts.append(f"maxRange correct ({actual_range})")
        else:
            feedback_parts.append(f"maxRange incorrect (got {actual_range}, expected {expected_range})")
    else:
        feedback_parts.append("maxRange field not found in saved world")

    # 2. horizontalFieldOfView
    fov_match = re.search(r'horizontalFieldOfView\s+([\d.]+)', wbt_content)
    if fov_match:
        actual_fov = float(fov_match.group(1))
        # Allow slight variance due to potential floating point input differences (e.g. 0.31 vs 0.314)
        if 0.31 <= actual_fov <= 0.32:
            score += 20
            feedback_parts.append(f"horizontalFieldOfView correct ({actual_fov})")
        else:
            feedback_parts.append(f"horizontalFieldOfView incorrect (got {actual_fov}, expected {expected_fov})")
    else:
        feedback_parts.append("horizontalFieldOfView field not found in saved world")

    # 3. rangeNoise
    noise_match = re.search(r'rangeNoise\s+([\d.]+)', wbt_content)
    if noise_match:
        actual_noise = float(noise_match.group(1))
        if abs(actual_noise - expected_noise) < 0.01:
            score += 20
            feedback_parts.append(f"rangeNoise correct ({actual_noise})")
        else:
            feedback_parts.append(f"rangeNoise incorrect (got {actual_noise}, expected {expected_noise})")
    else:
        feedback_parts.append("rangeNoise field not found in saved world")

    # 4. radarCrossSection
    rcs_match = re.search(r'radarCrossSection\s+([\d.]+)', wbt_content)
    if rcs_match:
        actual_rcs = float(rcs_match.group(1))
        if abs(actual_rcs - expected_rcs) < 1.0:
            score += 30
            feedback_parts.append(f"radarCrossSection correct ({actual_rcs})")
        else:
            feedback_parts.append(f"radarCrossSection incorrect (got {actual_rcs}, expected {expected_rcs})")
    else:
        feedback_parts.append("radarCrossSection field not found in saved world. Remember it must be set on the LEAD_VEHICLE.")

    # --- VLM Trajectory Check (Secondary Anti-Gaming) ---
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = """Look at these screenshots from a Webots robotics simulation session.
Did the user interact with the scene tree on the left side to edit properties of nodes (like 'front_radar' and 'LEAD_VEHICLE')?
Respond in JSON format: {"edited_scene_tree": true/false}"""
                vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if not parsed.get('edited_scene_tree', True):
                        logger.warning("VLM indicated scene tree might not have been edited.")
        except Exception as e:
            logger.info(f"VLM verification skipped or failed: {e}")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }