#!/usr/bin/env python3
"""
Verifier for collision_config_map task.

Scoring (100 points):
  - Criterion 1 (10 pts): CSV exists and is new
  - Criterion 2 (15 pts): CSV has >= 50 configuration rows
  - Criterion 3 (15 pts): Valid structure, >= 3 joints varied, both collision states exist
  - Criterion 4 (10 pts): Spatial diversity of end-effector (>= 15 distinct, >= 0.05 m spread)
  - Criterion 5 (15 pts): JSON report valid and consistent (totals match)
  - Criterion 6 (10 pts): Obstacle positions plausible (>= 3, mutually >= 0.1 m apart)
  - Criterion 7 (25 pts): VLM verifies trajectory showing coding and simulation control
  
Pass threshold: 70
Anti-gaming checks:
  - Do-nothing score: 0
  - Identical configs/all-collide fail criteria 3 & 4
  - VLM ensures trajectory actually shows work and Python execution
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/collision_config_map_result.json"

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully completed a robotics simulation task in CoppeliaSim.

TASK: The agent needed to write a Python script using the ZMQ Remote API to programmatically place at least 3 obstacles around a robot arm, sweep through 50+ joint configurations, and check for collisions.

Examine these trajectory frames (and final screenshot). Look for:
1. A code editor or terminal showing a Python script being written or executed.
2. The script should be interacting with the CoppeliaSim API (e.g., sim.createPrimitiveShape, sim.checkCollision).
3. The CoppeliaSim window should show the robot arm moving to different configurations or new obstacles appearing in the scene.

Did the agent actually write and run code to perform this task?
Respond in JSON format:
{
    "wrote_code": true/false,
    "simulation_controlled": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what you see in the frames."
}"""

def verify_collision_config_map(traj, env_info, task_info):
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
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    score = 0
    feedback = []

    # Criterion 1: CSV exists and is new (10 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 10
        feedback.append("CSV file created after task start (+10)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but predates task start — stale file")
    else:
        feedback.append("collision_map.csv not found")

    # Criterion 2: >= 50 configuration rows (15 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 50:
        score += 15
        feedback.append(f"CSV has {row_count} configurations (>= 50 required) (+15)")
    elif row_count >= 20:
        score += 7
        feedback.append(f"CSV has {row_count} configurations (partial: 7/15)")
    else:
        feedback.append(f"CSV has {row_count} configurations (need >= 50)")

    # Criterion 3: Valid structure & joint diversity (15 pts)
    csv_analysis = result.get("csv_analysis", {})
    if isinstance(csv_analysis, dict):
        valid_structure = csv_analysis.get("valid_structure", False)
        joints_varied = int(csv_analysis.get("joints_varied_count", 0))
        both_states = csv_analysis.get("has_both_collision_states", False)
        
        if valid_structure and joints_varied >= 3 and both_states:
            score += 15
            feedback.append(f"Valid CSV structure, {joints_varied} joints varied, both collision states found (+15)")
        elif valid_structure and joints_varied >= 1 and both_states:
            score += 7
            feedback.append(f"Partial structure match: {joints_varied} joints varied, both collision states found (partial: 7/15)")
        elif valid_structure and joints_varied >= 3:
            score += 7
            feedback.append(f"Valid CSV structure, {joints_varied} joints varied, but lacks both collision states (partial: 7/15)")
        elif not valid_structure:
            feedback.append("CSV missing required columns (ee_x/y/z or collision)")
        else:
            feedback.append(f"Insufficient joint diversity ({joints_varied} joints varied) or collision states")
    else:
        feedback.append("Could not parse CSV analysis")

    # Criterion 4: Spatial diversity of end-effector (10 pts)
    if isinstance(csv_analysis, dict):
        unique_ee = int(csv_analysis.get("unique_ee_positions", 0))
        ee_spread = float(csv_analysis.get("ee_spread_m", 0.0))
        
        if unique_ee >= 15 and ee_spread >= 0.05:
            score += 10
            feedback.append(f"EE positions diverse: {unique_ee} unique, {ee_spread:.3f}m spread (+10)")
        elif unique_ee >= 5 and ee_spread >= 0.01:
            score += 5
            feedback.append(f"EE positions somewhat diverse: {unique_ee} unique, {ee_spread:.3f}m spread (partial: 5/10)")
        else:
            feedback.append(f"EE position diversity too low: {unique_ee} unique, {ee_spread:.3f}m spread")
            
    # Criterion 5: JSON report valid and consistent (15 pts)
    json_analysis = result.get("json_analysis", {})
    if isinstance(json_analysis, dict):
        valid_fields = json_analysis.get("valid_fields", False)
        total_configs = int(json_analysis.get("total_configs", 0))
        obs_placed = int(json_analysis.get("obstacles_placed", 0))
        
        if result.get("json_exists") and result.get("json_is_new") and valid_fields and total_configs >= 50 and obs_placed >= 3:
            score += 15
            feedback.append(f"JSON report valid, internally consistent, {total_configs} configs, {obs_placed} obstacles (+15)")
        elif result.get("json_exists") and result.get("json_is_new") and valid_fields:
            score += 7
            feedback.append(f"JSON report exists and is consistent but config/obstacle counts are low (partial: 7/15)")
        elif result.get("json_exists") and result.get("json_is_new"):
            score += 4
            feedback.append("JSON report exists but missing required fields or inconsistent totals (partial: 4/15)")
        else:
            feedback.append("collision_report.json not found or not new")
    else:
        feedback.append("Could not parse JSON analysis")

    # Criterion 6: Obstacle positions plausible (10 pts)
    if isinstance(json_analysis, dict):
        valid_pos = json_analysis.get("valid_obstacle_positions", False)
        if valid_pos:
            score += 10
            feedback.append("Obstacle positions are plausible and spatially distinct (+10)")
        else:
            feedback.append("Obstacle positions missing, invalid, or too close together")

    # Criterion 7: VLM Verification of coding/simulation activity (25 pts)
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=images
            )
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("wrote_code") and parsed.get("simulation_controlled"):
                score += 25
                feedback.append("VLM confirmed trajectory shows coding and simulation control (+25)")
            elif parsed.get("wrote_code") or parsed.get("simulation_controlled"):
                score += 10
                feedback.append("VLM partially confirmed trajectory activity (partial: 10/25)")
            else:
                feedback.append("VLM did not detect coding or simulation control in trajectory")
        else:
            feedback.append("No trajectory images available for VLM verification")
    else:
        feedback.append("VLM verification function not available")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }