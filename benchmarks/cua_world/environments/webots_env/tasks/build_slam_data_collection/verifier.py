#!/usr/bin/env python3
"""
Verifier for build_slam_data_collection task.

A field robotics researcher must build from scratch:
1. A Webots world with a corridor arena (4 walls), a Pioneer 3-AT robot with
   Lidar, GPS, IMU, and wheel encoders.
2. A Python data-logging controller that reads all sensors and writes CSV.

This is a stub verifier — basic structural checks only.
Full verification is handled by vlm_checklist_verifier.

Scoring (100 points total):
  - World file exists and created during task: 10 points
  - Controller file exists and created during task: 10 points
  - World has valid VRML header: 5 points
  - World contains WorldInfo with basicTimeStep: 5 points
  - World contains RectangleArena or Floor: 5 points
  - World contains >= 4 Solid wall nodes: 10 points
  - World contains Pioneer3at robot: 10 points
  - World contains Lidar sensor: 5 points
  - World contains GPS sensor: 5 points
  - World contains InertialUnit sensor: 5 points
  - Controller has valid Python syntax: 10 points
  - Controller has Robot import and step loop: 10 points
  - Controller writes to CSV file: 5 points
  - Controller sets motor velocity: 5 points

Pass threshold: 65 points
"""

import json
import re
import tempfile
import os
import logging
import py_compile

logger = logging.getLogger(__name__)


def verify_build_slam_data_collection(traj, env_info, task_info):
    """
    Verify that the SLAM benchmark world and controller were correctly built.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    controller_path = metadata.get('controller_path',
        '/home/ga/webots_projects/slam_bench/controllers/slam_logger/slam_logger.py')
    world_path = metadata.get('world_output_path',
        '/home/ga/Desktop/slam_benchmark.wbt')

    score = 0
    feedback_parts = []

    # --- Read export JSON ---
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    export_result = {}

    try:
        copy_from_env('/tmp/slam_benchmark_result.json', result_file.name)
        with open(result_file.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read export result JSON: {e}")
    finally:
        try:
            os.unlink(result_file.name)
        except Exception:
            pass

    task_start = int(export_result.get('task_start_timestamp', 0))

    # --- Copy world file ---
    wbt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_tmp.close()
    wbt_content = None

    try:
        copy_from_env(world_path, wbt_tmp.name)
        with open(wbt_tmp.name, 'r', encoding='utf-8', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy world file: {e}")
    finally:
        try:
            os.unlink(wbt_tmp.name)
        except Exception:
            pass

    # --- Copy controller file ---
    py_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    py_tmp.close()
    py_content = None

    try:
        copy_from_env(controller_path, py_tmp.name)
        with open(py_tmp.name, 'r', encoding='utf-8', errors='replace') as f:
            py_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy controller file: {e}")

    # ================================================================
    # SCORING — WORLD FILE
    # ================================================================

    # 1. World file exists and created during task (10 pts)
    world_exists = export_result.get('world_exists', False)
    world_size = export_result.get('world_size_bytes', 0)
    world_mtime = int(export_result.get('world_mtime', 0))

    if world_exists and world_size > 500 and wbt_content:
        if world_mtime >= task_start or task_start == 0:
            score += 10
            feedback_parts.append("World file created during task")
        else:
            feedback_parts.append("World file exists but predates task start (stale)")
    else:
        feedback_parts.append(f"World file not found or too small at {world_path}")
        # Still check controller even if world is missing

    # 2. Controller file exists and created during task (10 pts)
    ctrl_exists = export_result.get('controller_exists', False)
    ctrl_size = export_result.get('controller_size_bytes', 0)
    ctrl_mtime = int(export_result.get('controller_mtime', 0))

    if ctrl_exists and ctrl_size > 100 and py_content:
        if ctrl_mtime >= task_start or task_start == 0:
            score += 10
            feedback_parts.append("Controller file created during task")
        else:
            feedback_parts.append("Controller file exists but predates task start (stale)")
    else:
        feedback_parts.append(f"Controller file not found or too small at {controller_path}")

    # --- World content checks (only if we have content) ---
    if wbt_content:
        # 3. Valid VRML header (5 pts)
        if re.search(r'^#VRML_SIM', wbt_content):
            score += 5
            feedback_parts.append("Valid VRML header")

        # 4. WorldInfo with basicTimeStep (5 pts)
        ts_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
        if ts_match:
            ts = int(ts_match.group(1))
            max_ts = metadata.get('verification_ranges', {}).get('basicTimeStep_max', 32)
            if ts <= max_ts:
                score += 5
                feedback_parts.append(f"basicTimeStep={ts} (acceptable)")
            else:
                feedback_parts.append(f"basicTimeStep={ts} too high (expected <={max_ts})")
        else:
            feedback_parts.append("basicTimeStep not found in WorldInfo")

        # 5. RectangleArena or Floor (5 pts)
        if re.search(r'(RectangleArena|Floor)\s*\{', wbt_content):
            score += 5
            feedback_parts.append("Arena/floor present")

        # 6. >= 4 wall Solid nodes (10 pts)
        wall_defs = re.findall(r'DEF\s+WALL_\w+\s+Solid\s*\{', wbt_content)
        solid_count = len(wall_defs)
        if solid_count == 0:
            # Fallback: count any Solid nodes with Box geometry
            solid_count = len(re.findall(r'Solid\s*\{', wbt_content))
        if solid_count >= 4:
            score += 10
            feedback_parts.append(f"{solid_count} wall Solid nodes found")
        elif solid_count >= 2:
            score += 5
            feedback_parts.append(f"Only {solid_count} wall Solid nodes (expected >=4)")
        else:
            feedback_parts.append(f"Only {solid_count} wall Solid nodes (expected >=4)")

        # 7. Pioneer 3-AT robot (10 pts)
        if re.search(r'Pioneer3at\s*\{', wbt_content, re.IGNORECASE):
            score += 10
            feedback_parts.append("Pioneer 3-AT robot present")
        elif re.search(r'Robot\s*\{', wbt_content):
            score += 5
            feedback_parts.append("Robot node found but not Pioneer 3-AT")
        else:
            feedback_parts.append("No robot node found")

        # 8. Lidar sensor (5 pts)
        if re.search(r'Lidar\s*\{', wbt_content):
            score += 5
            feedback_parts.append("Lidar sensor present")

        # 9. GPS sensor (5 pts)
        if re.search(r'GPS\s*\{', wbt_content):
            score += 5
            feedback_parts.append("GPS sensor present")

        # 10. InertialUnit sensor (5 pts)
        if re.search(r'InertialUnit\s*\{', wbt_content):
            score += 5
            feedback_parts.append("InertialUnit sensor present")

    # ================================================================
    # SCORING — CONTROLLER FILE
    # ================================================================

    if py_content:
        # 11. Valid Python syntax (10 pts)
        try:
            py_compile.compile(py_tmp.name, doraise=True)
            score += 10
            feedback_parts.append("Controller Python syntax valid")
        except py_compile.PyCompileError:
            feedback_parts.append("Controller has Python syntax errors")

        # 12. Robot import + step loop (10 pts)
        has_import = bool(re.search(
            r'(from\s+controller\s+import\s+.*Robot|import\s+controller)', py_content))
        has_loop = bool(re.search(r'while\s+.*step\s*\(', py_content))

        if has_import and has_loop:
            score += 10
            feedback_parts.append("Robot imported and simulation loop present")
        elif has_import:
            score += 5
            feedback_parts.append("Robot imported but simulation loop missing")
        elif has_loop:
            score += 5
            feedback_parts.append("Simulation loop present but Robot import missing")
        else:
            feedback_parts.append("Missing Robot import and simulation loop")

        # 13. CSV file writing (5 pts)
        has_csv = bool(re.search(
            r'(open\s*\(.*csv|\.write\s*\(|csv\.writer|slam_log)', py_content))
        if has_csv:
            score += 5
            feedback_parts.append("CSV logging present in controller")
        else:
            feedback_parts.append("No CSV logging found in controller")

        # 14. Motor velocity control (5 pts)
        has_motor = bool(re.search(r'setVelocity', py_content))
        if has_motor:
            score += 5
            feedback_parts.append("Motor velocity control present")
        else:
            feedback_parts.append("No setVelocity calls found in controller")

    # Clean up temp file
    try:
        os.unlink(py_tmp.name)
    except Exception:
        pass

    passed = score >= 65

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
