#!/usr/bin/env python3
"""
Verifier for the v_block_profile SolveSpace task.

Combines programmatic file parsing of the .slvs file to verify exact geometric 
coordinates against the expected 15-point V-block set, plus VLM trajectory 
verification to ensure the agent actually interacted with the UI.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List, Set, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected 15-point normalized geometry for the V-block
EXPECTED_POINTS = {
    (0.0, 0.0), (60.0, 0.0), (60.0, 15.0), (55.0, 15.0), (55.0, 25.0),
    (60.0, 25.0), (60.0, 40.0), (45.0, 40.0), (30.0, 25.0), (15.0, 40.0),
    (0.0, 40.0), (0.0, 25.0), (5.0, 25.0), (5.0, 15.0), (0.0, 15.0)
}

VLM_PROMPT = """You are verifying if an AI agent successfully completed a CAD task in SolveSpace.
The task required drawing a 15-sided 2D closed profile of a machining V-block and fully constraining it.

Look at these screenshots taken during the agent's workflow:
1. Did the agent use the SolveSpace UI (tools, menus, canvas) to draw line segments?
2. Did the agent apply constraints (like horizontal, vertical, dimensions, perpendicular) visible in the Property Browser or as symbols on the canvas?
3. Does the final shape look like a V-block (a rectangle with a V-notch on top and two rectangular slots on the sides)?

Respond in JSON format:
{
    "used_ui_to_draw": true/false,
    "applied_constraints": true/false,
    "shape_resembles_vblock": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of evidence seen in the screenshots"
}"""

def parse_slvs_geometry(file_path: str) -> Dict[str, Any]:
    """Parse the SolveSpace plain-text format to extract points, lines, and constraints."""
    objects = []
    current_obj = {}
    current_prefix = None
    
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or '=' not in line:
                continue
                
            key, val = line.split('=', 1)
            prefix = key.split('.')[0] if '.' in key else key
            
            if prefix in ['Entity', 'Constraint', 'Request', 'Group']:
                if current_prefix != prefix or key.endswith('.h.v'):
                    if current_obj:
                        objects.append((current_prefix, current_obj))
                    current_obj = {}
                    current_prefix = prefix
                    
            if current_prefix:
                k = key[len(current_prefix)+1:] if '.' in key else key
                current_obj[k] = val
                
    if current_obj:
        objects.append((current_prefix, current_obj))
        
    # Extract points (Entity.type=10000)
    points = {}
    for obj_type, obj in objects:
        if obj_type == "Entity" and obj.get("type") == "10000":
            try:
                points[obj["h.v"]] = (float(obj["actPoint.x"]), float(obj["actPoint.y"]))
            except KeyError:
                pass
                
    # Extract points that belong to line segments (Entity.type=11000)
    line_points = set()
    for obj_type, obj in objects:
        if obj_type == "Entity" and obj.get("type") == "11000":
            pt0 = obj.get("point[0].v")
            pt1 = obj.get("point[1].v")
            if pt0 in points:
                line_points.add(points[pt0])
            if pt1 in points:
                line_points.add(points[pt1])
                
    # Extract constraint types
    constraint_types = set()
    for obj_type, obj in objects:
        if obj_type == "Constraint":
            c_type = obj.get("type")
            if c_type:
                constraint_types.add(c_type)
                
    return {
        "line_points": list(line_points),
        "constraint_types": list(constraint_types)
    }

def verify_v_block_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    
    score = 0
    feedback = []
    
    try:
        # Get result metadata
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        # Check anti-gaming criteria
        if not result.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Output .slvs file does not exist. Task failed."}
            
        if not result.get("file_modified_during_task"):
            return {"passed": False, "score": 0, "feedback": "File was not modified during the task execution (Anti-gaming triggered)."}

        if result.get("file_size_bytes", 0) < 500:
            return {"passed": False, "score": 0, "feedback": "Saved file is too small to contain a valid profile."}
            
        score += 10
        feedback.append("File exists and was modified during task (+10)")

        # Parse geometry
        try:
            copy_from_env("/tmp/v_block_profile_eval.slvs", temp_slvs.name)
            parsed_data = parse_slvs_geometry(temp_slvs.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse .slvs file: {e}"}

        line_points = parsed_data.get("line_points", [])
        constraints = parsed_data.get("constraint_types", [])
        
        # Check geometric closure / line count
        if len(line_points) >= 15:
            score += 15
            feedback.append("Sufficient line segments detected (+15)")
        else:
            feedback.append(f"Expected at least 15 points in the profile, found {len(line_points)}.")
            
        if line_points:
            min_x = min(p[0] for p in line_points)
            min_y = min(p[1] for p in line_points)
            max_x = max(p[0] for p in line_points)
            max_y = max(p[1] for p in line_points)
            
            width = max_x - min_x
            height = max_y - min_y
            
            # Check Overall Dimensions
            width_ok = abs(width - 60.0) <= 0.5
            height_ok = abs(height - 40.0) <= 0.5
            if width_ok and height_ok:
                score += 10
                feedback.append("Bounding box dimensions correct (+10)")
            else:
                feedback.append(f"Bounding box incorrect: W={width:.1f} (expected 60), H={height:.1f} (expected 40)")

            # Normalize points
            normalized_pts = {(round(p[0] - min_x, 1), round(p[1] - min_y, 1)) for p in line_points}
            
            # Check exact expected points
            matched_points = 0
            for ex, ey in EXPECTED_POINTS:
                # Find if any point is within tolerance
                if any(abs(ex - nx) <= 0.5 and abs(ey - ny) <= 0.5 for nx, ny in normalized_pts):
                    matched_points += 1

            if matched_points == 15:
                score += 25
                feedback.append("Perfect geometric coordinate match (15/15 points) (+25)")
            elif matched_points >= 10:
                score += 15
                feedback.append(f"Partial geometric match ({matched_points}/15 points) (+15)")
            else:
                feedback.append(f"Poor geometric match ({matched_points}/15 points).")

            # Check Constraints used
            has_h = "80" in constraints
            has_v = "70" in constraints
            has_perp = "100" in constraints or "40" in constraints
            has_dist = "30" in constraints or "31" in constraints
            
            if has_h and has_v and has_dist:
                score += 10
                feedback.append("Required parametric constraints applied (+10)")
            else:
                feedback.append("Missing required constraints (Horizontal, Vertical, or Distance).")
        else:
            feedback.append("No line geometry found in the file.")

        # VLM Trajectory Verification
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    used_ui = parsed.get("used_ui_to_draw", False)
                    applied_c = parsed.get("applied_constraints", False)
                    shape_ok = parsed.get("shape_resembles_vblock", False)
                    
                    if used_ui:
                        score += 10
                        feedback.append("VLM confirms UI interaction (+10)")
                    if applied_c:
                        score += 10
                        feedback.append("VLM confirms constraint application (+10)")
                    if shape_ok:
                        score += 10
                        feedback.append("VLM confirms shape matches a V-block (+10)")
                    else:
                        feedback.append(f"VLM Note: {parsed.get('reasoning', 'No reasoning provided')}")
                else:
                    feedback.append("VLM query failed or returned no success.")
            except Exception as e:
                logger.error(f"VLM Verification failed: {e}")
                feedback.append("VLM Verification encountered an error.")
        else:
            feedback.append("VLM capability not available, skipping visual scoring.")

    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }