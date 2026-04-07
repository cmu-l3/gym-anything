#!/usr/bin/env python3
"""
Verifier for the TopoCal spatial filtering task (crop_points_to_boundary@1).

Uses MULTIPLE INDEPENDENT SIGNALS for verification:
1. File existence and creation time checks (prevents reusing old files).
2. Rigorous programmatic content analysis of the exported .xyz file (bounding box & count constraints).
3. VLM trajectory verification to ensure the agent physically drafted the polyline and deleted points using the CAD UI (prevents programmatic script spoofing).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crop_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Retrieve the exported metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    points_exists = result.get('points_file_exists', False)
    project_exists = result.get('project_file_exists', False)
    points_created_during_task = result.get('points_created_during_task', False)

    if project_exists:
        score += 10
        feedback_parts.append("Project saved successfully (+10)")
    else:
        feedback_parts.append("Project file not found")

    if points_exists and points_created_during_task:
        score += 10
        feedback_parts.append("Points exported successfully during task window (+10)")
    elif points_exists:
        feedback_parts.append("Points file exists but was NOT created during task window (Anti-gaming triggered)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Exported points file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Programmatic analysis of the exported XYZ file & Ground truth validation
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_points = tempfile.NamedTemporaryFile(delete=False, suffix='.xyz')
    gt_count = 0
    
    try:
        copy_from_env("C:\\workspace\\data\\ground_truth.txt", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_count = int(f.read().strip())
            
        copy_from_env("C:\\workspace\\data\\site_aoi_points.xyz", temp_points.name)
        
        valid_points = 0
        outlier_points = 0
        total_points = 0
        
        with open(temp_points.name, 'r') as f:
            for line in f:
                # Handle space or comma delimited export
                parts = line.replace(',', ' ').strip().split()
                if len(parts) >= 3:
                    try:
                        x = float(parts[1])
                        y = float(parts[2])
                        total_points += 1
                        
                        # Apply a 5-meter tolerance to account for slight manual drafting inaccuracies
                        if 4995.0 <= x <= 5305.0 and 4895.0 <= y <= 5205.0:
                            valid_points += 1
                        else:
                            outlier_points += 1
                    except ValueError:
                        continue
                        
        if total_points == 0:
            feedback_parts.append("Exported points file is empty or improperly formatted")
        else:
            # Check bounding box rigor
            if outlier_points == 0:
                score += 30
                feedback_parts.append("All exported points rigorously reside within the AOI boundary (+30)")
            else:
                feedback_parts.append(f"Failed AOI constraint: {outlier_points} points found outside the boundary")

            # Check point count vs ground truth
            count_diff = abs(total_points - gt_count)
            if count_diff <= 5:
                score += 30
                feedback_parts.append(f"Retained point count ({total_points}) matches ground truth ({gt_count}) (+30)")
            elif count_diff <= 25:
                score += 15
                feedback_parts.append(f"Retained point count ({total_points}) partially matches ground truth ({gt_count}) (+15)")
            else:
                feedback_parts.append(f"Incorrect point deletion. Found {total_points} points, expected ~{gt_count}")
                
    except Exception as e:
        feedback_parts.append(f"Error parsing points file: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
        if os.path.exists(temp_points.name):
            os.unlink(temp_points.name)

    # 3. VLM Verification (Trajectory confirmation of workflow)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    prompt = """You are verifying an agent's CAD drafting workflow.
Look at these chronological trajectory screenshots of a topographics CAD software (TopoCal).
Did the agent:
1. Draw a rectangular boundary (polyline) around a subset of the points?
2. Use selection tools to isolate and delete points outside the boundary?
3. In the final states, are only the points inside the rectangular boundary visible on the screen?

Respond with JSON:
{
    "polyline_drawn": true/false,
    "points_deleted_via_ui": true/false,
    "final_state_cropped": true/false
}"""
    
    if query_vlm:
        images = frames + [final_img] if final_img else frames
        vlm_res = query_vlm(images=images, prompt=prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("polyline_drawn") and parsed.get("points_deleted_via_ui") and parsed.get("final_state_cropped"):
                score += 20
                feedback_parts.append("VLM confirms correct UI polyline drafting and point cropping (+20)")
            else:
                feedback_parts.append("VLM could not confirm the required UI interactions for drafting and deletion.")
        else:
            feedback_parts.append("VLM query failed or returned no result.")
    else:
        feedback_parts.append("VLM tool unavailable for trajectory verification.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }