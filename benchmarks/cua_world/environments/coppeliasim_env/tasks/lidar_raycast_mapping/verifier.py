#!/usr/bin/env python3
"""
Verifier for lidar_raycast_mapping task.

Scoring (100 points):
  - Criterion 1 (20 pts): Required files (TTT, CSV, JSON) exist and were created after task start.
  - Criterion 2 (25 pts): CSV Structure & Geometry (bounds ~±3.0m). Validates 6x6m room size.
  - Criterion 3 (15 pts): Obstacle Detection (Internal hits < 2.5m). Validates internal geometry.
  - Criterion 4 (40 pts): VLM Trajectory Verification. Verifies the agent actually built/scripted the scene in CoppeliaSim.

Pass threshold: 70
Anti-gaming checks:
  - Do-nothing score: 0
  - Pure hallucination script: Fails VLM trajectory and geometric bound tolerance.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/lidar_raycast_mapping_result.json"

VLM_PROMPT = """You are verifying a robotics simulation task.
The agent was asked to write a script to programmatically build a 6x6m enclosed room with obstacles in CoppeliaSim, and sweep a ray sensor.

Look at these trajectory frames and determine if the agent did the work:
1. Is there evidence of CoppeliaSim being used? (Either the 3D viewport showing primitive walls/obstacles being generated, OR a code editor/terminal showing CoppeliaSim Python ZMQ Remote API scripts like `sim.createPrimitiveShape` or `sim.readProximitySensor`).
2. Does it look like a genuine attempt to generate geometry and perform raycasting?

Respond in JSON format:
{
    "coppeliasim_or_script_visible": true/false,
    "genuine_attempt": true/false,
    "reasoning": "Brief explanation"
}"""

def verify_lidar_raycast_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Read exported results
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

    # Parse nested results
    ttt = result.get("ttt", {})
    csv_data = result.get("csv", {})
    json_data = result.get("json", {})
    csv_stats = csv_data.get("stats", {})
    json_stats = json_data.get("stats", {})

    # Criterion 1: Files Exist & Are New (20 points)
    files_ok = 0
    if ttt.get("exists") and ttt.get("is_new") and ttt.get("size_bytes", 0) > 10000:
        files_ok += 1
    if csv_data.get("exists") and csv_data.get("is_new"):
        files_ok += 1
    if json_data.get("exists") and json_data.get("is_new") and json_stats.get("valid"):
        files_ok += 1

    if files_ok == 3:
        score += 20
        feedback.append("All output files (TTT, CSV, JSON) correctly exported and new (+20)")
    elif files_ok > 0:
        score += 10
        feedback.append(f"Some output files exported ({files_ok}/3) (partial: 10/20)")
    else:
        feedback.append("Output files missing or stale")

    # Criterion 2: CSV Structure & Geometric validation of the room (25 points)
    if csv_stats.get("valid"):
        rows = csv_stats.get("row_count", 0)
        max_x, min_x = csv_stats.get("max_x", 0), csv_stats.get("min_x", 0)
        max_y, min_y = csv_stats.get("max_y", 0), csv_stats.get("min_y", 0)
        
        # Room is 6x6 centered at origin -> Bounds should be near 3.0 and -3.0
        x_bound_ok = (2.7 <= max_x <= 3.3) and (-3.3 <= min_x <= -2.7)
        y_bound_ok = (2.7 <= max_y <= 3.3) and (-3.3 <= min_y <= -2.7)

        if rows >= 100 and x_bound_ok and y_bound_ok:
            score += 25
            feedback.append(f"Geometry valid: 6x6m room boundaries detected in CSV (+25)")
        elif rows >= 10:
            score += 10
            feedback.append(f"CSV valid but bounds (X:[{min_x:.1f},{max_x:.1f}], Y:[{min_y:.1f},{max_y:.1f}]) don't match 6x6m room (partial: 10/25)")
        else:
            feedback.append("CSV has insufficient points for geometry validation")
    else:
        feedback.append("CSV data invalid or unparseable")

    # Criterion 3: Obstacles Detected (15 points)
    if csv_stats.get("valid"):
        internal_hits = csv_stats.get("internal_hits", 0)
        if internal_hits > 0:
            score += 15
            feedback.append(f"Obstacles detected: {internal_hits} internal hits recorded (+15)")
        else:
            feedback.append("No internal obstacles detected in point cloud")

    # Criterion 4: VLM Trajectory Verification (40 points)
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("coppeliasim_or_script_visible") and parsed.get("genuine_attempt"):
                        score += 40
                        feedback.append("VLM verified CoppeliaSim/API scripting activity (+40)")
                    else:
                        feedback.append(f"VLM verification failed: {parsed.get('reasoning', 'No genuine activity detected')}")
                else:
                    feedback.append("VLM query failed during verification")
            else:
                feedback.append("No trajectory frames available for VLM verification")
        except Exception as e:
            feedback.append(f"VLM Exception: {str(e)}")
    else:
        # Fallback if VLM unavailable, give partial credit to not completely block if geometry is perfect
        if score >= 45:
            score += 25
            feedback.append("VLM unavailable, awarding partial heuristic points (+25)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }