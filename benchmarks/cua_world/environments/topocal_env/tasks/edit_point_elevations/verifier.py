#!/usr/bin/env python3
"""
Verifier for Edit Point Elevations task.

VERIFICATION STRATEGY:
1. File check: Correctly named output file must exist and have been created after task start.
2. Data parsing: Read the exported file robustly regardless of delimiter (commas, spaces, tabs).
3. Target Points (IDs 21-25): Must match the 'expected' ground truth (original inflated value - 1.52m).
4. Unchanged Points: Other sampled points must match their 'original' inflated values to prevent blanket changes.
5. VLM trajectory: Verify the agent used the UI to edit points.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a CAD/Surveying task in TopoCal.
Did the agent open the point list/editor window ('Listado de Puntos' or 'Editar Puntos') and manually edit point elevation (Z) values?
Did they subsequently navigate the export menu/dialog to save a text file?
Answer in JSON:
{
    "opened_point_editor": true/false,
    "edited_values": true/false,
    "exported_file": true/false
}"""

def parse_exported_points(filepath):
    """Robustly parse TopoCal exported points looking for numeric data."""
    points = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                # Find all sequences of numbers (allows negative and decimals)
                nums = re.findall(r'-?\d+\.\d+|-?\d+', line)
                if len(nums) >= 4:
                    try:
                        # Standard TopoCal export is P,X,Y,Z...
                        pid = str(int(float(nums[0])))
                        z_val = float(nums[3])
                        points[pid] = z_val
                    except ValueError:
                        continue
    except Exception as e:
        logger.error(f"Failed to parse exported points: {e}")
    return points

def verify_edit_point_elevations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_points = metadata.get('target_points', ["21", "22", "23", "24", "25"])
    tolerance = metadata.get('tolerance_m', 0.02)
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch task result JSON
    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", result_tmp.name)
        with open(result_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to read task result"}
    finally:
        os.unlink(result_tmp.name)

    # 2. Check File Existence & Timestamps (Anti-Gaming)
    if result.get('output_exists'):
        score += 10
        feedback_parts.append("Output file found")
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("Warning: File timestamp predates task start")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 3. Fetch Ground Truth
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/ground_truth.json", gt_tmp.name)
        with open(gt_tmp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to read ground truth"}
    finally:
        os.unlink(gt_tmp.name)

    # 4. Fetch and Parse Exported Points
    points_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("C:/tmp/corrected_points.txt", points_tmp.name)
        exported_points = parse_exported_points(points_tmp.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": "Failed to extract exported points file"}
    finally:
        os.unlink(points_tmp.name)

    # Evaluate exported points
    if len(exported_points) > 0:
        score += 10
        feedback_parts.append(f"Successfully parsed {len(exported_points)} points")
        
        # Check targets (IDs 21-25)
        correct_targets = 0
        for pid in target_points:
            if pid in exported_points and pid in gt['expected']:
                expected_z = gt['expected'][pid]
                actual_z = exported_points[pid]
                if abs(actual_z - expected_z) <= tolerance:
                    correct_targets += 1
                else:
                    feedback_parts.append(f"Point {pid} incorrect: {actual_z} (Expected ~{expected_z})")
            else:
                feedback_parts.append(f"Point {pid} missing from export")
                
        # 10 points per correctly edited target
        score += (correct_targets * 8)
        if correct_targets == len(target_points):
            feedback_parts.append("All target elevations correctly adjusted")

        # Check collateral damage (Sample unchanged points)
        unchanged_samples = ["1", "10", "30", "50"]
        unchanged_correct = 0
        for pid in unchanged_samples:
            if pid in exported_points and pid in gt['original']:
                if abs(exported_points[pid] - gt['original'][pid]) <= tolerance:
                    unchanged_correct += 1
                    
        if unchanged_correct == len(unchanged_samples):
            score += 15
            feedback_parts.append("Unchanged points properly preserved")
        else:
            feedback_parts.append("Warning: Collateral damage detected on non-target points")
    else:
        feedback_parts.append("Could not parse numeric point data from export")

    # 5. VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames + [final])
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("opened_point_editor") and parsed.get("edited_values"):
                score += 15
                feedback_parts.append("VLM verified point editor usage")

    # Determine Pass/Fail (Threshold: 70)
    # Must have the file, and at least 3 points correctly edited
    key_criteria = result.get('output_exists') and (correct_targets >= 3)
    passed = (score >= 70) and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }