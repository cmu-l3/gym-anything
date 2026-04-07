#!/usr/bin/env python3
"""
Verifier for obstacle_path_planning task.

Scoring System (100 pts total):
1. CSV/JSON exist and are new: 10 pts
2. Path contains >= 10 waypoints: 15 pts
3. Path is spatially diverse (length >= 0.3m, dist >= 0.2m): 15 pts
4. Collision quality (>= 80% safe, positive clearance): 15 pts
5. JSON report complete and valid: 20 pts
6. VLM Trajectory Verification (Obstacles created & arm moved): 25 pts

Pass threshold: 70 points
Anti-gaming:
- File timestamps strictly enforced
- Start/goal distance ensures path actually traverses space
- VLM trajectory check verifies real visual changes in simulation
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/task_result.json"

VLM_PROMPT = """You are evaluating a robotics simulation task in CoppeliaSim.
The user was asked to CREATE multiple block-like obstacles (cuboids) in the robot's workspace and move the robot arm between them.

Review the provided screenshots from the simulation trajectory.
Determine the following:
1. Did the user create visible new obstacles (like boxes/cuboids) in the workspace around the robot arm?
2. Did the robot arm actually move through space over the course of the trajectory?

Respond strictly in this JSON format:
{
    "obstacles_created": true/false,
    "robot_moved": true/false,
    "reasoning": "Brief explanation of your observations"
}
"""


def verify_obstacle_path_planning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Fetch JSON result file
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: Files exist and are new (10 pts)
    csv_ok = result.get("csv_exists") and result.get("csv_is_new")
    json_ok = result.get("json_exists") and result.get("json_is_new")
    
    if csv_ok and json_ok:
        score += 10
        feedback.append("Output files created successfully (+10)")
    elif csv_ok or json_ok:
        score += 5
        feedback.append("Only one output file created successfully (partial: 5/10)")
    else:
        feedback.append("Output files missing or not created during task")

    # Criterion 2: Path Waypoints (15 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 10:
        score += 15
        feedback.append(f"CSV contains {row_count} waypoints (+15)")
    elif row_count > 0:
        score += 5
        feedback.append(f"CSV contains {row_count} waypoints (need >= 10, partial: 5/15)")
    else:
        feedback.append("CSV contains 0 waypoints")

    # Criterion 3: Spatial Diversity (15 pts)
    csv_analysis = result.get("csv_analysis", {})
    if isinstance(csv_analysis, dict):
        has_coords = csv_analysis.get("has_coords", False)
        path_length = float(csv_analysis.get("path_length_m", 0.0))
        dist = float(csv_analysis.get("start_goal_dist", 0.0))
        
        if has_coords and path_length >= 0.3 and dist >= 0.2:
            score += 15
            feedback.append(f"Path spatially diverse: len={path_length:.2f}m, disp={dist:.2f}m (+15)")
        elif has_coords and path_length > 0:
            score += 5
            feedback.append(f"Path has insufficient length/displacement (len={path_length:.2f}m) (partial: 5/15)")
        elif not has_coords:
            feedback.append("CSV lacks valid spatial coordinates")
    else:
        feedback.append("Failed to analyze CSV spatial data")

    # Criterion 4: Collision Quality (15 pts)
    if isinstance(csv_analysis, dict):
        cf_pct = float(csv_analysis.get("collision_free_pct", 0.0))
        valid_cl = csv_analysis.get("valid_clearance", False)
        
        if cf_pct >= 0.8 and valid_cl:
            score += 15
            feedback.append(f"Collision avoidance verified: {cf_pct*100:.0f}% safe, valid clearance data (+15)")
        elif cf_pct > 0 or valid_cl:
            score += 7
            feedback.append(f"Partial collision avoidance data: {cf_pct*100:.0f}% safe (partial: 7/15)")
        else:
            feedback.append("No valid collision/clearance data in path")

    # Criterion 5: JSON Valid & Complete (20 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        tot_wp = int(json_fields.get("total_waypoints", 0))
        
        if json_ok and has_fields and tot_wp >= 10:
            score += 20
            feedback.append("JSON report complete with all required fields (+20)")
        elif json_ok and has_fields:
            score += 10
            feedback.append("JSON report complete but total_waypoints insufficient (partial: 10/20)")
        elif json_ok:
            feedback.append("JSON report is missing required fields")

    # Criterion 6: VLM Trajectory Verification (25 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        images = frames + [final_shot] if final_shot else frames
        
        if images:
            vlm_resp = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                obst_created = parsed.get("obstacles_created", False)
                rob_moved = parsed.get("robot_moved", False)
                
                if obst_created and rob_moved:
                    score += 25
                    feedback.append("VLM confirms obstacles created and robot moved (+25)")
                elif obst_created or rob_moved:
                    score += 10
                    feedback.append("VLM confirms partial workflow completion (partial: 10/25)")
                else:
                    feedback.append("VLM indicates missing obstacles or no robot movement")
            else:
                feedback.append("VLM query failed or format invalid")
        else:
            feedback.append("No trajectory images available for VLM verification")
    else:
        feedback.append("VLM query capability not available")

    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }