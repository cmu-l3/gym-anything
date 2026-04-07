#!/usr/bin/env python3
"""
Verifier for guitar_fretboard_layout task.

Verification Strategy:
1. Programmatic File Check: Parses the saved `.slvs` text file to find the solved points.
   The parametric solver calculates the exact X-coordinates of the fret slots where they 
   intersect the tapered edges. The agent cannot know these exact floating-point values 
   without properly setting up the constraints in the CAD engine.
2. VLM Trajectory Verification: Ensures the agent actively worked in SolveSpace and 
   produced the visual shape expected.
"""

import json
import os
import tempfile
import logging
from typing import List, Tuple, Dict

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying a parametric CAD task in SolveSpace.
The user was asked to draw a classical guitar fretboard layout: a tapered symmetric trapezoid outline with 3 horizontal fret lines inside it.

Review these screenshots of the agent's workflow:
1. Did the agent successfully use SolveSpace's UI to draw the trapezoid and lines?
2. Are dimension constraints visible on the screen (e.g., numbers like 480, 43, 56, 36.48, 70.92)?
3. Does the final image show the completed layout?

Respond with a JSON object:
{
    "used_solvespace": true/false,
    "dimensions_visible": true/false,
    "layout_looks_correct": true/false,
    "reasoning": "Brief explanation"
}
"""

def extract_points_from_slvs(file_path: str) -> List[Tuple[float, float]]:
    """Parse the text-based .slvs file to extract all active 2D points calculated by the solver."""
    points = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        curr_x = None
        curr_y = None
        
        for line in lines:
            line = line.strip()
            # New entity block indicator
            if line.startswith("Entity.h.v="):
                if curr_x is not None and curr_y is not None:
                    points.append((curr_x, curr_y))
                curr_x, curr_y = None, None
            elif line.startswith("Entity.actPoint.x="):
                try:
                    curr_x = float(line.split("=")[1])
                except ValueError:
                    pass
            elif line.startswith("Entity.actPoint.y="):
                try:
                    curr_y = float(line.split("=")[1])
                except ValueError:
                    pass
                    
        # Append the last point if it exists
        if curr_x is not None and curr_y is not None:
            points.append((curr_x, curr_y))
            
    except Exception as e:
        logger.error(f"Failed to parse slvs file: {e}")
        
    return points

def verify_fretboard_layout(traj, env_info, task_info) -> Dict:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_points = metadata.get('expected_points', [])
    tol = metadata.get('tolerance_mm', 0.05)
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SolveSpace/fretboard.slvs')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        if os.path.exists(temp_result.name) and os.path.getsize(temp_result.name) > 0:
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Validate output exists and was created properly
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "File fretboard.slvs was not created."}
    if result.get('output_size_bytes', 0) < 500:
        return {"passed": False, "score": 0, "feedback": "File fretboard.slvs is empty or invalid."}
    
    score += 10
    feedback_parts.append("File exists")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File newly created")

    # 2. Retrieve the .slvs file to parse solver geometry
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    actual_points = []
    try:
        copy_from_env(expected_output_path, temp_slvs.name)
        actual_points = extract_points_from_slvs(temp_slvs.name)
    except Exception as e:
        logger.error(f"Failed to copy/read .slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    # 3. Geometric Verification
    # We look for the presence of solved intersection points in the geometry.
    solved_features = 0
    for ep in expected_points:
        target_x = ep['x']
        target_y = ep['y']
        
        # Look for this coordinate pair (using absolute X because of symmetry)
        found = False
        for px, py in actual_points:
            if abs(abs(px) - target_x) <= tol and abs(py - target_y) <= tol:
                found = True
                break
        
        if found:
            solved_features += 1
            logger.info(f"Found match for {ep['name']}: X~{target_x}, Y~{target_y}")
        else:
            logger.warning(f"Missing point {ep['name']}: X~{target_x}, Y~{target_y}")

    geom_score = min(50, solved_features * 10)
    score += geom_score
    feedback_parts.append(f"Geometry accurate ({solved_features}/{len(expected_points)} targets solved)")

    # 4. VLM Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
        
        try:
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=frames
            )
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('used_solvespace', False):
                score += 10
                feedback_parts.append("VLM confirmed active UI usage")
            if parsed.get('dimensions_visible', False):
                score += 10
            if parsed.get('layout_looks_correct', False):
                score += 10
                
            feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning', 'none')}")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM validation skipped due to error")
    else:
        # Give free VLM points if the function is not provided, since geometry proves the work
        score += 30

    # Ensure max score doesn't exceed 100
    score = min(100, score)
    
    # Passing conditions: Must have created file, solved the outline (at least 2 points), and got > 60 points
    key_criteria_met = output_exists and solved_features >= 2
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }