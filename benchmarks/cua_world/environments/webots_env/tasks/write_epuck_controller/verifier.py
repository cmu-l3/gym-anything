#!/usr/bin/env python3
"""
Verifier for write_epuck_controller task.

A robotics engineer must write a Python obstacle avoidance controller from scratch
and save the Webots world.

Scoring (100 points total):
  - Controller file exists and created during task: 10 points
  - World file saved to Desktop: 10 points
  - Python Syntax is valid: 15 points
  - Robot class imported and instantiated: 20 points
  - Proximity sensors initialized properly: 15 points
  - Webots simulation loop present: 15 points
  - Motor velocity control logic present: 15 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging
import py_compile

logger = logging.getLogger(__name__)


def verify_write_epuck_controller(traj, env_info, task_info):
    """
    Verify that the Python controller was written correctly and world was saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    controller_path = metadata.get('controller_path', '/home/ga/webots_projects/epuck_obstacle/controllers/obstacle_avoider/obstacle_avoider.py')
    world_path = metadata.get('world_output_path', '/home/ga/Desktop/epuck_avoidance.wbt')

    score = 0
    feedback_parts = []
    
    # --- Check export JSON ---
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    
    try:
        copy_from_env('/tmp/write_epuck_controller_result.json', result_file.name)
        with open(result_file.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not read export result JSON: {e}")
        export_result = {}

    task_start = export_result.get('task_start_timestamp', 0)
    
    # --- Copy Python Controller ---
    py_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    py_file.close()
    py_content = None

    try:
        copy_from_env(controller_path, py_file.name)
        with open(py_file.name, 'r', encoding='utf-8', errors='replace') as f:
            py_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy controller file: {e}")

    # --- Copy World File ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(world_path, wbt_file.name)
        with open(wbt_file.name, 'r', encoding='utf-8', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy world file: {e}")
        
    try:
        os.unlink(wbt_file.name)
    except Exception:
        pass

    # ================================================================
    # SCORING CRITERIA
    # ================================================================

    # 1. Controller file exists and created during task (10 pts)
    ctrl_exists = export_result.get('controller_exists', False)
    ctrl_size = export_result.get('controller_size_bytes', 0)
    ctrl_mtime = export_result.get('controller_mtime', 0)

    if ctrl_exists and ctrl_size > 50 and py_content:
        if ctrl_mtime >= task_start or task_start == 0:
            score += 10
            feedback_parts.append("Controller file successfully created")
        else:
            feedback_parts.append("Controller file appears to be from before task start (stale)")
    else:
        feedback_parts.append(f"Controller file not found or empty at {controller_path}")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. World file saved (10 pts)
    world_exists = export_result.get('world_exists', False)
    world_size = export_result.get('world_size_bytes', 0)
    
    if world_exists and world_size > 500 and wbt_content:
        score += 10
        feedback_parts.append("World file correctly saved to Desktop")
    else:
        feedback_parts.append("World file not saved to Desktop (use File > Save World As)")

    # 3. Python Syntax (15 pts)
    syntax_valid = False
    try:
        py_compile.compile(py_file.name, doraise=True)
        syntax_valid = True
        score += 15
        feedback_parts.append("Python syntax is valid")
    except py_compile.PyCompileError as e:
        feedback_parts.append("Python syntax error in controller script")
    finally:
        try:
            os.unlink(py_file.name)
        except Exception:
            pass

    # 4. Robot class imported and instantiated (20 pts)
    has_import = bool(re.search(r'(from\s+controller\s+import\s+.*Robot|import\s+controller)', py_content))
    has_instantiation = bool(re.search(r'Robot\s*\(\s*\)', py_content))
    
    if has_import and has_instantiation:
        score += 20
        feedback_parts.append("Robot properly imported and instantiated")
    elif has_import:
        score += 10
        feedback_parts.append("Robot imported but not instantiated correctly")
    else:
        feedback_parts.append("Missing Webots Robot import/instantiation")

    # 5. Proximity sensors initialized properly (15 pts)
    ps_matches = re.findall(r'ps[0-7]', py_content)
    has_ps = len(set(ps_matches)) >= 2
    has_enable = '.enable' in py_content or 'enable(' in py_content
    
    if has_ps and has_enable:
        score += 15
        feedback_parts.append("Proximity sensors enabled properly")
    elif has_ps:
        score += 7
        feedback_parts.append("Proximity sensors referenced but enable() not found")
    else:
        feedback_parts.append("Proximity sensors (ps0-ps7) not utilized properly")

    # 6. Webots simulation loop present (15 pts)
    # Looking for a while loop containing .step
    has_loop = bool(re.search(r'while\s+.*step\s*\(', py_content))
    
    if has_loop:
        score += 15
        feedback_parts.append("Simulation step loop correctly implemented")
    else:
        feedback_parts.append("Missing or incorrect 'while robot.step(timestep) != -1:' loop")

    # 7. Motor velocity control logic (15 pts)
    has_motors = bool(re.search(r'(left\s*wheel\s*motor|right\s*wheel\s*motor|motor)', py_content, re.IGNORECASE))
    has_set_vel = 'setVelocity' in py_content
    
    if has_motors and has_set_vel:
        score += 15
        feedback_parts.append("Motor velocity control properly referenced")
    else:
        feedback_parts.append("Missing motor initialization or setVelocity() calls")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }