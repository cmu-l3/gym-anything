#!/usr/bin/env python3
"""
Verifier for configure_rl_environment task.

A Machine Learning Engineer configures a Webots world for external RL training.
Modifications required:
1. WorldInfo -> basicTimeStep: 16
2. WorldInfo -> randomSeed: 42
3. DEF AGENT E-puck -> controller: "<extern>"
4. DEF AGENT E-puck -> supervisor: TRUE
5. Solid (red sphere) -> DEF RL_TARGET

Scoring (100 points total):
  - File exists and was saved during task: 10 points
  - basicTimeStep == 16: 15 points
  - randomSeed == 42: 15 points
  - controller == "<extern>": 20 points
  - supervisor == TRUE: 20 points
  - DEF RL_TARGET Solid: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_configure_rl_environment(traj, env_info, task_info):
    """
    Verify that the RL environment configuration world has been properly saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/rl_env_ready.wbt')
    expected_timestep = metadata.get('expected_timestep', 16)
    expected_seed = metadata.get('expected_seed', 42)
    expected_controller = metadata.get('expected_controller', '<extern>')
    expected_supervisor = metadata.get('expected_supervisor', 'TRUE')
    expected_target_def = metadata.get('expected_target_def', 'RL_TARGET')

    score = 0
    feedback_parts = []
    
    # 1. Check metadata JSON from export_result.sh
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env('/tmp/rl_task_result.json', result_json_path)
        with open(result_json_path, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read metadata JSON: {e}")
        export_data = {"file_exists": False, "file_created_during_task": False}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    if not export_data.get("file_exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }

    if not export_data.get("file_created_during_task"):
        feedback_parts.append("Warning: Output file timestamp indicates it might not have been created during this session.")
    else:
        score += 10
        feedback_parts.append("File saved successfully.")

    # 2. Copy the actual .wbt file to verify contents
    wbt_file_path = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt').name
    wbt_content = ""
    try:
        copy_from_env(output_path, wbt_file_path)
        with open(wbt_file_path, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Could not copy .wbt file from VM: {e}")
        return {
            "passed": False,
            "score": score,
            "feedback": f"Could not read the saved .wbt file to verify its contents."
        }
    finally:
        if os.path.exists(wbt_file_path):
            os.unlink(wbt_file_path)

    # Validate that we successfully read the file and it has substantial content
    if len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": "Saved world file is suspiciously small or empty."
        }

    # --- Check basicTimeStep ---
    timestep_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
    if timestep_match and int(timestep_match.group(1)) == expected_timestep:
        score += 15
        feedback_parts.append(f"basicTimeStep set to {expected_timestep}.")
    else:
        actual_timestep = timestep_match.group(1) if timestep_match else "not found"
        feedback_parts.append(f"basicTimeStep incorrect (found {actual_timestep}, expected {expected_timestep}).")

    # --- Check randomSeed ---
    seed_match = re.search(r'randomSeed\s+(\d+)', wbt_content)
    if seed_match and int(seed_match.group(1)) == expected_seed:
        score += 15
        feedback_parts.append(f"randomSeed set to {expected_seed}.")
    else:
        actual_seed = seed_match.group(1) if seed_match else "not found"
        feedback_parts.append(f"randomSeed incorrect (found {actual_seed}, expected {expected_seed}).")

    # --- Check AGENT controller ---
    # Look for the controller property inside the DEF AGENT robot block
    # It might look like: controller "<extern>"
    controller_match = re.search(r'DEF\s+AGENT\s+[^{]+\{.*?controller\s+"([^"]+)"', wbt_content, re.DOTALL)
    if not controller_match:
        # Fallback if AGENT DEF was somehow mangled, just look for the extern controller globally
        controller_match = re.search(r'controller\s+"([^"]+)"', wbt_content)
        
    if controller_match and controller_match.group(1) == expected_controller:
        score += 20
        feedback_parts.append(f"Controller set to '{expected_controller}'.")
    else:
        actual_ctrl = controller_match.group(1) if controller_match else "not found"
        feedback_parts.append(f"Controller incorrect (found '{actual_ctrl}', expected '{expected_controller}').")

    # --- Check AGENT supervisor ---
    # Supervisor might look like: supervisor TRUE
    supervisor_match = re.search(r'DEF\s+AGENT\s+[^{]+\{.*?supervisor\s+(TRUE|FALSE)', wbt_content, re.DOTALL)
    if not supervisor_match:
        # Global fallback
        supervisor_match = re.search(r'supervisor\s+(TRUE|FALSE)', wbt_content)

    if supervisor_match and supervisor_match.group(1) == expected_supervisor:
        score += 20
        feedback_parts.append("Supervisor privileges enabled.")
    else:
        actual_sup = supervisor_match.group(1) if supervisor_match else "not found"
        feedback_parts.append(f"Supervisor incorrect (found {actual_sup}, expected {expected_supervisor}).")

    # --- Check DEF RL_TARGET Solid ---
    # Ensure there is a DEF RL_TARGET before a Solid block.
    # Ex: DEF RL_TARGET Solid {
    target_def_match = re.search(r'DEF\s+RL_TARGET\s+Solid\b', wbt_content)
    if target_def_match:
        score += 20
        feedback_parts.append("DEF RL_TARGET assigned to Solid.")
    else:
        feedback_parts.append("DEF RL_TARGET not found on the target Solid.")

    # Determine if the task passed based on the threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }