#!/usr/bin/env python3
"""
Verifier for robot_cmm_calibration_scan task.

Robust multi-signal verification checking:
  - Timestamp logic preventing pre-existing file exploits.
  - CSV parsing to extract kinematic values.
  - Mathematical analysis measuring if surface topologies conform to intended geometries.
  - VLM usage for visual confirmation of objects entering the scene.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/robot_cmm_calibration_scan_result.json"

def verify_robot_cmm_calibration_scan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found \u2014 export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: Files Existence & Freshness (10 pts)
    files_ok = True
    if not (result.get("csv_exists") and result.get("csv_is_new")):
        files_ok = False
        feedback.append("CSV file missing or stale")
    if not (result.get("json_exists") and result.get("json_is_new")):
        files_ok = False
        feedback.append("JSON file missing or stale")
    if not (result.get("ttt_exists") and result.get("ttt_is_new")):
        files_ok = False
        feedback.append("TTT file missing or stale")

    if files_ok:
        score += 10
        feedback.append("All output files (CSV, JSON, TTT) created after task start (+10)")

    # Criterion 2: CSV Data Volume (15 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 40:
        score += 15
        feedback.append(f"CSV has {row_count} rows (>= 40 required) (+15)")
    elif row_count >= 10:
        score += 5
        feedback.append(f"CSV has {row_count} rows (partial: 5/15)")
    else:
        feedback.append(f"CSV has {row_count} rows (need >= 40)")

    num_detected = 0
    # Criterion 3: Topological Validity (30 pts)
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict):
        has_cols = analysis.get("has_required_cols", False)
        z_vals = analysis.get("surface_z_values", [])
        
        if has_cols and z_vals:
            # Check for clusters around expected steps: 0.02, 0.04, 0.06, 0.08
            expected_steps = [0.02, 0.04, 0.06, 0.08]
            detected_steps = set()
            
            for val in z_vals:
                for step in expected_steps:
                    # Small tolerance (0.005) handles kinematic fluctuations
                    if abs(val - step) <= 0.005:
                        detected_steps.add(step)
                        break
            
            num_detected = len(detected_steps)
            if num_detected >= 3:
                score += 30
                feedback.append(f"Topological valid: detected {num_detected} distinct step heights {sorted(list(detected_steps))} (+30)")
            elif num_detected > 0:
                score += 10
                feedback.append(f"Partial topological validity: detected {num_detected} distinct step heights (partial: 10/30)")
            else:
                feedback.append("Surface Z values do not cluster around expected step heights (0.02, 0.04, 0.06, 0.08)")
        elif not has_cols:
            feedback.append("CSV lacks required columns (ee_z, sensor_dist, surface_z)")
        else:
            feedback.append("No valid surface_z values found in CSV")
    else:
        feedback.append("Could not parse CSV analysis")

    # Criterion 4: JSON Report Valid (10 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict) and json_fields.get("has_fields", False):
        score += 10
        feedback.append("JSON report has all required fields (+10)")
    else:
        feedback.append("JSON report missing or lacks required fields")

    # Criterion 5: Scene Artifact Verification (15 pts)
    ttt_size = int(result.get("ttt_size", 0))
    if result.get("ttt_exists") and result.get("ttt_is_new") and ttt_size > 50000:
        score += 15
        feedback.append(f"TTT scene file valid, size: {ttt_size/1024:.1f} KB (+15)")
    elif result.get("ttt_exists") and result.get("ttt_is_new"):
        score += 5
        feedback.append(f"TTT scene file exists but size too small: {ttt_size/1024:.1f} KB (partial: 5/15)")
    else:
        feedback.append("TTT scene file missing or stale")

    # Criterion 6: VLM Trajectory Verification (20 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are evaluating if an agent successfully set up a Robot CMM Calibration Scan in CoppeliaSim.
Look at these trajectory frames and the final screenshot.
Did the agent:
1. Construct a step gauge block consisting of multiple adjoining steps (cuboids)?
2. Attach a proximity sensor pointing downward from the robot's end-effector?

Respond with JSON in this format:
{
    "constructed_step_gauge": true/false,
    "sensor_attached": true/false,
    "reasoning": "Brief explanation"
}"""
            if images:
                vlm_result = query_vlm(prompt=prompt, images=images)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("constructed_step_gauge"): 
                        score += 10
                        feedback.append("VLM: Step gauge block constructed (+10)")
                    if parsed.get("sensor_attached"): 
                        score += 10
                        feedback.append("VLM: Sensor visibly attached (+10)")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")

    # Pass logic enforces strict structural criteria with a generous 60% threshold accommodating for potential VLM hallucinations
    passed = score >= 60 and row_count >= 40 and num_detected >= 3
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }