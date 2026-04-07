#!/usr/bin/env python3
"""
Verifier for robotic_extrusion_profiling task.

Scoring (100 points):
  - Fresh Execution (10 pts): Output files exist and timestamps are newer than task start.
  - Data Completeness (15 pts): CSV contains >= 100 rows and required columns. JSON has fields.
  - Spatial Accuracy (25 pts): CSV X and Y bounding ranges are ~0.30m (circle of radius 0.15m).
  - Dynamic Accuracy (20 pts): Velocity averages ~0.094 m/s (completing circle in 10 seconds).
  - Physics Realism (10 pts): Tracking error is > 0, indicating physics solver lag/realism.
  - VLM Trajectory (20 pts): VLM verifies the robot actually moved in the trajectory frames.

Pass threshold: 70
Anti-gaming: Do-nothing scores 0. Spoofed perfect mathematics (tracking error 0) misses realism points.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/robotic_extrusion_profiling_result.json"


def verify_robotic_extrusion_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

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
        if os.path.exists(tmp.name):
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    score = 0
    feedback = []

    # 1. Fresh Execution (10 pts)
    csv_fresh = result.get("csv_exists") and result.get("csv_is_new")
    json_fresh = result.get("json_exists") and result.get("json_is_new")
    
    if csv_fresh and json_fresh:
        score += 10
        feedback.append("Both output files created after task start (+10)")
    elif csv_fresh or json_fresh:
        score += 5
        feedback.append("Only one output file is new (partial: 5/10)")
    else:
        feedback.append("Output files not found or predate task start (stale files)")

    # 2. Data Completeness (15 pts)
    row_count = int(result.get("csv_row_count", 0))
    csv_stats = result.get("csv_stats", {})
    json_info = result.get("json_info", {})
    
    has_data = csv_stats.get("has_data", False)
    has_fields = json_info.get("has_fields", False)
    
    if row_count >= 100 and has_data and has_fields:
        score += 15
        feedback.append(f"Data is complete with {row_count} rows (+15)")
    elif row_count >= 50 and has_data:
        score += 7
        feedback.append(f"Partial data with {row_count} rows (partial: 7/15)")
    else:
        feedback.append(f"Insufficient data rows ({row_count}) or missing fields")

    # 3. Spatial Accuracy (25 pts)
    x_range = float(csv_stats.get("x_range", 0.0))
    y_range = float(csv_stats.get("y_range", 0.0))
    
    # 0.15m radius -> 0.30m diameter. Accept 10% tolerance (0.27 to 0.33)
    x_ok = 0.27 <= x_range <= 0.33
    y_ok = 0.27 <= y_range <= 0.33
    
    if x_ok and y_ok:
        score += 25
        feedback.append(f"Spatial accuracy verified: X span {x_range:.3f}m, Y span {y_range:.3f}m (+25)")
    elif x_range > 0.1 and y_range > 0.1:
        score += 10
        feedback.append(f"Partial spatial accuracy: X span {x_range:.3f}m, Y span {y_range:.3f}m (partial: 10/25)")
    else:
        feedback.append(f"Spatial geometry failed (Target ~0.30m): X={x_range:.3f}m, Y={y_range:.3f}m")

    # 4. Dynamic Accuracy (20 pts)
    mean_v = float(csv_stats.get("mean_v", 0.0))
    # Target velocity is 2*pi*r / 10s = ~0.0942 m/s. Accept 0.08 to 0.11 m/s
    if 0.08 <= mean_v <= 0.11:
        score += 20
        feedback.append(f"Dynamic tracking accurate: Mean velocity {mean_v:.3f} m/s (+20)")
    elif mean_v > 0.01:
        score += 5
        feedback.append(f"Inaccurate tracking velocity: Mean {mean_v:.3f} m/s (Target ~0.094 m/s) (partial: 5/20)")
    else:
        feedback.append("Robot velocity was negligible or zero")

    # 5. Physics Realism (10 pts)
    max_te = float(csv_stats.get("max_te", 0.0))
    if max_te > 0.0001:
        score += 10
        feedback.append("Physics realism validated: Non-zero tracking error detected (+10)")
    elif max_te == 0.0 and mean_v > 0:
        feedback.append("Perfect tracking error (0.0) indicates spoofed mathematical data rather than actual physics engine reading")

    # 6. VLM Trajectory Check (20 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames:
            imgs = frames + [final] if final else frames
            prompt = """Look at this sequence of screenshots from a 3D robot simulation. 
Did the robot arm actually move its position throughout these frames?
Respond in JSON format: {"robot_moved": true/false, "reasoning": "brief explanation"}"""
            
            try:
                res = query_vlm(images=imgs, prompt=prompt)
                parsed = res.get('parsed', {})
                if parsed.get('robot_moved', False):
                    vlm_score = 20
                    feedback.append("VLM verified robot movement from trajectory frames (+20)")
                else:
                    feedback.append("VLM determined the robot arm did NOT move")
            except Exception as e:
                feedback.append(f"VLM verification failed: {str(e)}")
        else:
            feedback.append("No trajectory frames available for VLM verification")
    else:
        feedback.append("VLM querying unavailable; skipping visual check")
        
    score += vlm_score

    # Determine final pass status
    key_criteria_met = csv_fresh and (0.27 <= x_range <= 0.33) and (0.08 <= mean_v <= 0.11)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }