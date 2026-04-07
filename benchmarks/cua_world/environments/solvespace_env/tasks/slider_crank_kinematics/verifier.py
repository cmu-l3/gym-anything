#!/usr/bin/env python3
"""
Verifier for slider_crank_kinematics task.

Verification Strategy:
1. File Checks: Verifies the slvs file was created/modified during the task.
2. Geometric Parsing: SolveSpace continuously solves mechanisms and saves absolute coordinates.
   We parse the .slvs file for `actPoint.x` and `actPoint.y`.
   Given lengths L1=25, L2=80, angle=45 deg, and origin (0,0):
   - Crank pin must be at: (25*cos(45), 25*sin(45)) ≈ (17.678, 17.678)
   - Slider must be at: (25*cos(45) + sqrt(80^2 - (25*sin(45))^2), 0) ≈ (95.700, 0)
3. VLM Trajectory: Verifies the user actually navigated the UI to place constraints.
"""

import json
import tempfile
import os
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected calculated coordinates
EXPECTED_ORIGIN = (0.0, 0.0)
EXPECTED_CRANK_PIN = (17.678, 17.678)
EXPECTED_SLIDER = (95.700, 0.0)
TOLERANCE = 0.5  # mm tolerance


def get_distance(p1, p2):
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)


def find_closest_point(points, target):
    if not points:
        return float('inf'), None
    closest = min(points, key=lambda p: get_distance(p, target))
    return get_distance(closest, target), closest


def parse_slvs_points(file_path):
    """Parse a .slvs file and extract all 2D point coordinates."""
    points = []
    curr_x = None
    curr_y = None
    
    try:
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('Entity.actPoint.x='):
                    curr_x = float(line.split('=')[1])
                elif line.startswith('Entity.actPoint.y='):
                    curr_y = float(line.split('=')[1])
                    if curr_x is not None:
                        points.append((curr_x, curr_y))
                        curr_x = None
                        curr_y = None
    except Exception as e:
        logger.error(f"Failed to parse slvs file: {e}")
        
    return points


def verify_slider_crank(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Fetch Task Metadata JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Early check for file existence/gaming
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Failed: The output file slider_crank.slvs was not created."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Failed: The output file was not created/modified during the task timeframe."}
        
    score += 10
    feedback.append("File creation verified.")

    # 2. Parse the Solved Geometry from .slvs
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    points = []
    try:
        copy_from_env("/tmp/slider_crank.slvs", temp_slvs.name)
        points = parse_slvs_points(temp_slvs.name)
    except Exception as e:
        feedback.append(f"Could not read geometry: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    if not points:
        return {"passed": False, "score": score, "feedback": "Failed: No geometric points found in the saved file."}

    # Evaluate geometry
    dist_origin, pt_origin = find_closest_point(points, EXPECTED_ORIGIN)
    dist_crank, pt_crank = find_closest_point(points, EXPECTED_CRANK_PIN)
    dist_slider, pt_slider = find_closest_point(points, EXPECTED_SLIDER)

    if dist_origin <= TOLERANCE:
        score += 10
        feedback.append("Origin point correct.")
    else:
        feedback.append(f"Missing origin point (closest: {pt_origin})")

    if dist_crank <= TOLERANCE:
        score += 25
        feedback.append(f"Crank geometry solved correctly (25mm at 45°).")
    else:
        feedback.append(f"Crank geometry incorrect (closest to pin: {pt_crank}, expected: {EXPECTED_CRANK_PIN}).")

    if dist_slider <= TOLERANCE:
        score += 35
        feedback.append(f"Slider geometry solved correctly (X={pt_slider[0]:.2f}, Y={pt_slider[1]:.2f}).")
    else:
        feedback.append(f"Slider mechanism incorrect (closest: {pt_slider}, expected: {EXPECTED_SLIDER}).")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            prompt = (
                "Review these screenshots of a user operating SolveSpace CAD software. "
                "Did the user actively sketch a 2-segment linkage and apply constraint dimensions? "
                "Look for the property browser or canvas showing distance dimensions (25, 80) and an angle constraint (45). "
                "Answer ONLY 'Yes' or 'No'."
            )
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and "yes" in vlm_response.lower()[:10]:
                vlm_score = 20
                feedback.append("VLM confirms workflow trajectory.")
            else:
                feedback.append("VLM could not confirm constraints in UI trajectory.")
        except Exception as e:
            feedback.append(f"VLM check failed: {e}")

    score += vlm_score

    # Determine passing state
    key_criteria_met = (dist_crank <= TOLERANCE) and (dist_slider <= TOLERANCE)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "origin_err_mm": dist_origin,
            "crank_err_mm": dist_crank,
            "slider_err_mm": dist_slider,
            "points_extracted": len(points)
        }
    }