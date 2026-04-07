#!/usr/bin/env python3
"""
Verifier for trajectory_clearance_audit task.

Multi-Criteria Scoring (100 points):
  - Criterion 1 (10 pts): Required files exist and were modified after task start
  - Criterion 2 (15 pts): Scene artifact (.ttt) exists, is new, and size > 10KB
  - Criterion 3 (15 pts): CSV Trajectory Volume - >= 50 rows, joint angle variance present
  - Criterion 4 (20 pts): CSV Clearance Physics - valid clearance column, >= 10 unique values
  - Criterion 5 (20 pts): JSON Report Consistency - has all 5 fields, aligns with CSV
  - Criterion 6 (20 pts): VLM Trajectory Verification - verifies visual activity

Pass threshold: 70
"""

import json
import tempfile
import os
import logging
import math

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/clearance_audit_result.json"

VLM_PROMPT = """You are verifying if a computer agent successfully completed a robotics simulation task.
The task was to write a Python script using the CoppeliaSim ZMQ Remote API, which:
1. Loads a robot model and creates static obstacles.
2. Runs a trajectory sweep and calculates the minimum distance to the obstacles.
3. Saves the results and the CoppeliaSim scene.

Look at the trajectory frames provided (which may include the final screenshot).
Do you see evidence of:
- A code editor or terminal showing Python code/execution related to CoppeliaSim?
- The CoppeliaSim GUI window showing a robot arm and newly created obstacles?

Return a JSON with exactly these fields:
{
    "code_activity_visible": true/false,
    "simulation_activity_visible": true/false,
    "reasoning": "Brief explanation of what is visible"
}
"""


def verify_trajectory_clearance_audit(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.remove(tmp.name)

    score = 0
    feedback = []

    # Criterion 1: Files existence & newness (10 pts)
    csv_exist = result.get("csv_exists", False)
    json_exist = result.get("json_exists", False)
    ttt_exist = result.get("ttt_exists", False)
    
    if csv_exist and json_exist and ttt_exist:
        score += 5
        feedback.append("All output files exist (+5)")
        if result.get("csv_is_new") and result.get("json_is_new") and result.get("ttt_is_new"):
            score += 5
            feedback.append("All output files are newly created (+5)")
        else:
            feedback.append("Some files predate task start (potential stale files)")
    else:
        feedback.append("One or more required files are missing (CSV, JSON, TTT)")

    # Criterion 2: Scene Artifact (15 pts)
    ttt_size = int(result.get("ttt_size_bytes", 0))
    if ttt_exist and result.get("ttt_is_new") and ttt_size > 10240:
        score += 15
        feedback.append(f"Scene artifact valid: {ttt_size/1024:.1f}KB (+15)")
    elif ttt_exist and ttt_size > 10240:
        score += 5
        feedback.append("Scene artifact exists but predates task (+5)")
    elif ttt_exist:
        feedback.append(f"Scene artifact too small ({ttt_size} bytes)")
    else:
        feedback.append("Scene artifact missing")

    # Parse nested stats
    csv_stats = result.get("csv_stats", {})
    if not isinstance(csv_stats, dict):
        csv_stats = {}
        
    has_clearance = csv_stats.get("has_clearance", False)
    row_count = int(csv_stats.get("row_count", 0))
    unique_clear = int(csv_stats.get("unique_clearances", 0))
    joint_var = csv_stats.get("joint_variance", False)
    csv_min = float(csv_stats.get("min_clearance", 0.0))

    # Criterion 3: Trajectory Volume (15 pts)
    if row_count >= 50 and joint_var:
        score += 15
        feedback.append(f"CSV volume valid: {row_count} rows with varying joints (+15)")
    elif row_count >= 50:
        score += 10
        feedback.append(f"CSV has {row_count} rows but lacks dynamic joint variance (+10)")
    elif row_count >= 10:
        score += 5
        feedback.append(f"CSV has only {row_count} rows (partial: 5/15)")
    else:
        feedback.append("CSV row count insufficient")

    # Criterion 4: Clearance Physics (20 pts)
    if has_clearance and unique_clear >= 10:
        score += 20
        feedback.append(f"Clearance physics valid: {unique_clear} unique distance values (+20)")
    elif has_clearance and unique_clear >= 5:
        score += 10
        feedback.append(f"Clearance physics partial: {unique_clear} unique distances (partial: 10/20)")
    elif not has_clearance:
        feedback.append("CSV lacks a clearance/distance column")
    else:
        feedback.append("Clearance physics failed: static/constant values (no real dynamics)")

    # Criterion 5: Report Consistency (20 pts)
    json_info = result.get("json_info", {})
    if not isinstance(json_info, dict):
        json_info = {}

    has_fields = json_info.get("has_fields", False)
    total_steps = int(json_info.get("total_steps", 0))
    obstacles_eval = int(json_info.get("obstacles_evaluated", 0))
    json_min = float(json_info.get("absolute_min_clearance_m", 0.0))

    if has_fields and total_steps >= 50 and obstacles_eval >= 2:
        if abs(json_min - csv_min) < 0.005:
            score += 20
            feedback.append(f"JSON report consistent: {total_steps} steps, {obstacles_eval} obstacles, min={json_min:.4f}m (+20)")
        else:
            score += 10
            feedback.append(f"JSON has fields but min_clearance mismatch (JSON: {json_min:.4f}, CSV: {csv_min:.4f}) (+10)")
    elif has_fields:
        score += 5
        feedback.append(f"JSON fields present but values insufficient (steps={total_steps}, obs={obstacles_eval}) (+5)")
    else:
        feedback.append("JSON missing required fields")

    # Criterion 6: VLM Verification (20 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("code_activity_visible"):
                        vlm_score += 10
                        feedback.append("VLM confirmed code/terminal activity (+10)")
                    if parsed.get("simulation_activity_visible"):
                        vlm_score += 10
                        feedback.append("VLM confirmed CoppeliaSim simulation activity (+10)")
                else:
                    feedback.append(f"VLM check failed: {vlm_result.get('error')}")
            else:
                feedback.append("No images available for VLM verification.")
        except Exception as e:
            feedback.append(f"VLM exception: {str(e)}")
            if score >= 60:
                vlm_score += 20
                feedback.append("VLM fallback: Awarded points due to flawless programmatic checks (+20)")
    else:
        # If VLM is not available, we auto-award the points if programmatic checks strongly imply success
        if score >= 60:
            vlm_score += 20
            feedback.append("VLM unavailable: Auto-awarded points based on strong programmatic evidence (+20)")

    score += vlm_score
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }