#!/usr/bin/env python3
"""
Verifier for dual_robot_interlock task.

Scoring System (100 pts total):
1. File Generation (10 pts) - CSV & JSON exist and are valid.
2. Kinematic Validity (20 pts) - >= 200 rows of valid physical motion without teleporting (max_step_dist < 0.2m).
3. Robot 1 Cycles (15 pts) - R1 completes >= 4 full physical cycles (Home -> Zone -> Home).
4. Robot 2 Cycles (15 pts) - R2 completes >= 4 full physical cycles.
5. Strict Interlock (30 pts) - 0 physical simultaneous violations (awarded ONLY if movement actually occurred).
6. Minimum Clearance (10 pts) - The physical min_ee_dist between arms never drops below 0.15m.

Also includes a VLM-based secondary verification to detect "spoofed" CSVs without visual simulation execution.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/dual_robot_interlock_result.json"

def verify_dual_robot_interlock(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    csv_exists = result.get("csv_exists", False)
    csv_is_new = result.get("csv_is_new", False)
    csv_analysis = result.get("csv_analysis", {})
    json_exists = result.get("json_exists", False)
    json_is_new = result.get("json_is_new", False)
    json_fields = result.get("json_fields", {})

    csv_valid = csv_analysis.get("valid", False)
    
    # 1. File Generation (10 pts)
    if csv_exists and csv_is_new and csv_valid and json_exists and json_is_new and json_fields.get("has_fields"):
        score += 10
        feedback.append("✅ Files generated successfully (+10)")
    else:
        feedback.append("❌ File generation incomplete or stale")
        
    # Variables for deeper analysis
    rows = csv_analysis.get("row_count", 0)
    max_step_dist = csv_analysis.get("max_step_dist", 999.0)
    r1_cycles = csv_analysis.get("r1_cycles", 0)
    r2_cycles = csv_analysis.get("r2_cycles", 0)
    simultaneous_violations = csv_analysis.get("simultaneous_violations", 0)
    min_ee_dist = csv_analysis.get("min_ee_dist", 0.0)

    # 2. Kinematic Validity (20 pts)
    # Check for at least 200 rows of data and ensure no huge "teleportation" jumps
    kinematics_valid = False
    if csv_valid and rows >= 200:
        if max_step_dist < 0.2:
            score += 20
            kinematics_valid = True
            feedback.append(f"✅ Kinematic Validity: {rows} rows, smooth motion (max jump: {max_step_dist:.3f}m) (+20)")
        else:
            feedback.append(f"❌ Kinematic Validity Failed: Object teleportation detected (max jump: {max_step_dist:.3f}m > 0.2m)")
    else:
        feedback.append(f"❌ Kinematic Validity Failed: Only {rows} rows (need >= 200)")

    # 3. Robot 1 Cycles (15 pts)
    if r1_cycles >= 4:
        score += 15
        feedback.append(f"✅ Robot 1 completed {r1_cycles} cycles (+15)")
    else:
        feedback.append(f"❌ Robot 1 completed {r1_cycles} cycles (need >= 4)")

    # 4. Robot 2 Cycles (15 pts)
    if r2_cycles >= 4:
        score += 15
        feedback.append(f"✅ Robot 2 completed {r2_cycles} cycles (+15)")
    else:
        feedback.append(f"❌ Robot 2 completed {r2_cycles} cycles (need >= 4)")

    # 5. Strict Interlock (30 pts)
    # Give points ONLY if they actually moved (prevent gaming by just having them sit in Home)
    if kinematics_valid and (r1_cycles > 0 or r2_cycles > 0):
        if simultaneous_violations == 0:
            score += 30
            feedback.append("✅ Strict Interlock: 0 simultaneous physical incursions (+30)")
        else:
            feedback.append(f"❌ Strict Interlock Failed: {simultaneous_violations} instances of dual zone occupation")
    elif not kinematics_valid:
         feedback.append("❌ Strict Interlock: Not evaluated (Kinematics invalid)")
    else:
         feedback.append("❌ Strict Interlock: No cycles completed, interlock trivialized")

    # 6. Minimum Clearance (10 pts)
    if kinematics_valid and (r1_cycles > 0 or r2_cycles > 0):
        if min_ee_dist >= 0.15:
            score += 10
            feedback.append(f"✅ Minimum Clearance: {min_ee_dist:.3f}m >= 0.15m (+10)")
        else:
             feedback.append(f"❌ Minimum Clearance Failed: Dropped to {min_ee_dist:.3f}m (collision risk)")

    # =========================================================================
    # VLM Anti-Gaming Check (Ensure visually that 2 robots were actually in the scene)
    # =========================================================================
    query_vlm = env_info.get("query_vlm")
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_prompt = (
                "Look at these sequential screenshots of a CoppeliaSim robotics simulation. "
                "Answer the following: Are there TWO robotic arms physically visible in the 3D scene? "
                "Respond in JSON format: {\"two_robots_visible\": true/false}"
            )
            vlm_result = query_vlm(images=images, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if not parsed.get("two_robots_visible", False):
                    # Severe penalty for spoofing a CSV without actually rendering two robots
                    score = max(0, score - 50)
                    feedback.append("⚠️ VLM PENALTY: Two robots were not visually detected in the simulation scene (-50)")
                else:
                    feedback.append("✅ VLM Verification: Two robots detected visually.")
    
    # Pass threshold is 75, strictly requiring some interlocking success and valid kinematics
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }