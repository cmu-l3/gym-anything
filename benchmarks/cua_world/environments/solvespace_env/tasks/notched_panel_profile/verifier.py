#!/usr/bin/env python3
"""
Verifier for notched_panel_profile task in SolveSpace.

Verification Strategy:
1. File Metadata: Checks if output file exists, has content, and was created/modified during task (anti-gaming).
2. Programmatic Geometry Check: Parses the text-based .slvs file to:
   - Verify presence of 12 line segments.
   - Verify bounding box is ~80x50mm.
   - Verify corner notches are present (points located 5mm from bounding edges).
   - Verify constraints are applied.
3. VLM Hybrid Check: Evaluates trajectory frames and final screenshot to confirm visually
   that a closed, stepped rectangle was created and constrained.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """
You are verifying a 2D CAD task in SolveSpace. 
The agent was asked to create a closed profile of a rectangular panel (80x50mm) with 5x5mm square notches removed from ALL FOUR corners.

Look at the trajectory frames and final screenshot to determine:
1. Did the agent draw a shape with corner notches on all 4 corners? (It should look like a cross or stepped rectangle).
2. Is the profile a fully closed loop?
3. Are all the segments completely straight (horizontal/vertical)?
4. Are dimension constraints (like 80, 50, 5) visible on the sketch?
5. Does the status indicate it is fully constrained? (Look for "OK" in green text in the property browser, or absence of red "DOF" text).

Respond in JSON format:
{
    "has_notches": true/false,
    "is_closed_loop": true/false,
    "is_constrained": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_notched_panel_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get('task_start', 0)
    file_exists = result.get('file_exists', False)
    file_size = result.get('file_size_bytes', 0)
    file_mtime = result.get('file_mtime', 0)

    if not file_exists or file_size < 500:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: Expected output file notched_panel.slvs not found or is empty."
        }
        
    if file_mtime <= task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: Output file was not modified during the task (anti-gaming check failed)."
        }
        
    score += 15
    feedback_parts.append("File correctly created/modified")

    # 2. Retrieve and parse the actual .slvs file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/notched_panel.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r') as f:
            slvs_content = f.read()
            
        # Programmatic Geometry Checks
        
        # A. Count Line Entities (type=11000 in SolveSpace)
        line_count = len(re.findall(r'Entity\.type=11000', slvs_content))
        if 10 <= line_count <= 14:
            score += 15
            feedback_parts.append(f"Correct line segment count ({line_count})")
        elif line_count >= 4:
            score += 5
            feedback_parts.append(f"Partial line segment count ({line_count})")
            
        # B. Count Constraints
        constraint_count = len(re.findall(r'AddConstraint', slvs_content))
        if constraint_count >= 15:
            score += 10
            feedback_parts.append(f"Good constraint density ({constraint_count})")
        elif constraint_count >= 5:
            score += 5
            feedback_parts.append(f"Some constraints found ({constraint_count})")
            
        # C. Coordinate Geometry Checks
        xs = [float(m) for m in re.findall(r'Entity\.actPoint\.x=([-\d.]+)', slvs_content)]
        ys = [float(m) for m in re.findall(r'Entity\.actPoint\.y=([-\d.]+)', slvs_content)]
        
        has_correct_bbox = False
        has_notches = False
        
        if len(xs) >= 8 and len(ys) >= 8:
            x_range = max(xs) - min(xs)
            y_range = max(ys) - min(ys)
            
            # Check Bounding Box (Allow 80x50 or 50x80 rotation)
            w_ok = abs(x_range - 80.0) < 5.0 and abs(y_range - 50.0) < 5.0
            w_ok_rot = abs(x_range - 50.0) < 5.0 and abs(y_range - 80.0) < 5.0
            
            if w_ok or w_ok_rot:
                has_correct_bbox = True
                score += 15
                feedback_parts.append(f"Bounding box correct ({x_range:.1f}x{y_range:.1f})")
            else:
                feedback_parts.append(f"Bounding box incorrect ({x_range:.1f}x{y_range:.1f})")
                
            # Check Notch Geometry (points located ~5mm inward from the bounding box edges)
            x_min, x_max = min(xs), max(xs)
            y_min, y_max = min(ys), max(ys)
            notch_pts = 0
            
            for x, y in zip(xs, ys):
                # Is point horizontally 5mm from left/right edge?
                near_x_notch = abs(x - (x_min + 5)) < 2.0 or abs(x - (x_max - 5)) < 2.0
                # Is point vertically 5mm from top/bottom edge?
                near_y_notch = abs(y - (y_min + 5)) < 2.0 or abs(y - (y_max - 5)) < 2.0
                
                at_y_edge = abs(y - y_min) < 1.0 or abs(y - y_max) < 1.0
                at_x_edge = abs(x - x_min) < 1.0 or abs(x - x_max) < 1.0
                
                if near_x_notch and at_y_edge:
                    notch_pts += 1
                if near_y_notch and at_x_edge:
                    notch_pts += 1
                    
            if notch_pts >= 4:
                has_notches = True
                score += 15
                feedback_parts.append("Notch geometry mathematically confirmed")
            elif notch_pts > 0:
                score += 5
                feedback_parts.append("Partial notch geometry detected")
                
    except Exception as e:
        logger.error(f"Error parsing .slvs file: {e}")
        feedback_parts.append(f"Error parsing geometry: {str(e)}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 3. VLM Hybrid Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            if frames and final:
                vlm_result = query_vlm(
                    images=frames + [final],
                    prompt=VERIFICATION_PROMPT
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    vlm_notches = parsed.get("has_notches", False)
                    vlm_closed = parsed.get("is_closed_loop", False)
                    vlm_constrained = parsed.get("is_constrained", False)
                    
                    if vlm_notches: vlm_score += 15
                    if vlm_closed: vlm_score += 10
                    if vlm_constrained: vlm_score += 5
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM Visual check: Notches={vlm_notches}, Closed={vlm_closed}, Constrained={vlm_constrained}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped/failed")

    # Determine Pass/Fail (Must score at least 65 and have the key criteria met programmatically)
    key_criteria_met = file_exists and (file_mtime > task_start) and (line_count >= 8)
    passed = (score >= 65) and key_criteria_met
    
    # Cap score at 100
    score = min(100, score)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }