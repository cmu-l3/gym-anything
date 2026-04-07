#!/usr/bin/env python3
"""
Verifier for kinematic_swept_volume_voxelization task.

Criteria evaluated:
1. File Existence & Freshness (15 pts)
2. Voxel Quantity Limit (>= 100 voxels) (15 pts)
3. Mathematical Consistency (25 pts)
   - CSV coordinates match indices * 0.05
   - JSON volume matches count * 0.05^3
4. Bounding Box Integrity (25 pts)
   - JSON bounds match the empirically calculated CSV bounds
5. Trajectory Complexity (20 pts)
   - JSON claims >= 2 joints swept >= 60 degrees
   - VLM verification confirms the robot actually moved in trajectory frames
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def list_match(l1: List[float], l2: List[float], tol: float = 1e-3) -> bool:
    if not isinstance(l1, list) or not isinstance(l2, list): return False
    if len(l1) != len(l2): return False
    return all(isinstance(a, (int, float)) and isinstance(b, (int, float)) and abs(a - b) < tol for a, b in zip(l1, l2))

def verify_kinematic_swept_volume_voxelization(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Read exported task_result.json
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
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
    json_exists = result.get("json_exists", False)
    json_is_new = result.get("json_is_new", False)
    
    # 1. File Existence & Freshness (15 pts)
    if csv_exists and csv_is_new and json_exists and json_is_new:
        score += 15
        feedback.append("Both output files created during task execution (+15).")
    elif csv_exists or json_exists:
        feedback.append("Files exist but may be stale or incomplete (0/15).")
    else:
        feedback.append("Required output files missing (0/15).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Voxel Quantity Limit (15 pts)
    rows = result.get("csv_rows", 0)
    if rows >= 100:
        score += 15
        feedback.append(f"CSV contains {rows} occupied voxels (>= 100) (+15).")
    elif rows >= 20:
        score += 5
        feedback.append(f"CSV contains {rows} occupied voxels (partial: 5/15).")
    else:
        feedback.append(f"CSV contains {rows} voxels, lacking sufficient trajectory coverage (0/15).")

    # 3. Mathematical Consistency (25 pts)
    csv_math = result.get("csv_math_consistent", False)
    json_data = result.get("json_data", {})
    
    vol_resolution = json_data.get("voxel_resolution_m", 0.0)
    total_voxels = json_data.get("total_occupied_voxels", 0)
    est_volume = json_data.get("estimated_volume_m3", 0.0)
    
    math_consistent = False
    if csv_math and abs(vol_resolution - 0.05) < 1e-5:
        expected_vol = total_voxels * (0.05 ** 3)
        if isinstance(est_volume, (int, float)) and abs(est_volume - expected_vol) < 1e-5:
            math_consistent = True
            
    if math_consistent and rows > 0:
        score += 25
        feedback.append("Voxel center math and total volume computation perfectly consistent (+25).")
    elif rows > 0:
        feedback.append("Mathematical inconsistencies found between CSV indices/coords or JSON volume (0/25).")
        
    # 4. Bounding Box Integrity (25 pts)
    json_has_fields = result.get("json_has_fields", False)
    bounds_match = False
    
    if json_has_fields and rows > 0:
        csv_min = result.get("csv_bounds_min", [])
        csv_max = result.get("csv_bounds_max", [])
        json_min = json_data.get("bounding_box_min_m", [])
        json_max = json_data.get("bounding_box_max_m", [])
        
        if list_match(csv_min, json_min) and list_match(csv_max, json_max):
            bounds_match = True
            
    if bounds_match:
        score += 25
        feedback.append("JSON bounding box matches empirical CSV extrema (+25).")
    elif json_has_fields:
        feedback.append("JSON bounding box does not match actual CSV bounds (0/25).")
    else:
        feedback.append("Missing bounding box fields in JSON (0/25).")

    # 5. Trajectory Complexity & VLM Verification (20 pts)
    joint_ranges = json_data.get("max_joint_ranges_swept_deg", {})
    joints_above_60 = sum(1 for v in joint_ranges.values() if isinstance(v, (int, float)) and v >= 60.0)
    
    claims_complex = joints_above_60 >= 2
    
    vlm_passed = False
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are verifying a robot simulation task. Look at these frames of CoppeliaSim.
            Did the robot arm move significantly (change its joint configurations and sweep through space) across these frames?
            If it remained completely stationary the entire time, or there is no robot arm visible, respond NO.
            If it clearly moved its joints and swept through space, respond YES.
            
            Return ONLY a valid JSON:
            {
                "robot_moved": true/false,
                "reasoning": "brief explanation"
            }"""
            
            vlm_res = query_vlm(prompt=prompt, images=images)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("robot_moved", False):
                    vlm_passed = True
                    logger.info(f"VLM confirmed movement: {parsed.get('reasoning')}")
                else:
                    logger.info(f"VLM denied movement: {parsed.get('reasoning')}")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            
    if claims_complex and vlm_passed:
        score += 20
        feedback.append("Trajectory swept >= 60° in >= 2 joints, visually confirmed by VLM (+20).")
    elif claims_complex:
        score += 10
        feedback.append("JSON claims sufficient joint sweep, but VLM could not confirm movement (partial: 10/20).")
    else:
        feedback.append(f"Trajectory insufficient: only {joints_above_60} joints swept >= 60° (0/20).")

    key_criteria_met = (rows >= 100) and math_consistent and bounds_match
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }