#!/usr/bin/env python3
"""
Verifier for L-Beam Centroid Statics task.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_l_beam_centroid_statics(traj, env_info, task_info):
    """
    Verifies the construction of the L-beam, centroid calculation, and angle measurement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_G = (metadata.get('centroid_x', 2.0), metadata.get('centroid_y', 3.0))
    expected_angle = metadata.get('expected_angle_deg', 21.8)
    sub_c1 = metadata.get('sub_centroids_set1', [[1,4], [4,1]])
    sub_c2 = metadata.get('sub_centroids_set2', [[1,5], [3,1]])
    tolerance = metadata.get('tolerance', 0.1)

    # Fetch result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully.")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found, but timestamp check failed.")
    else:
        feedback.append("File not found.")

    points = result.get("points", [])
    polygons = result.get("polygons", [])
    angles = result.get("angles", [])
    lines = result.get("lines", [])

    # 2. Polygon Check (20 pts)
    # The L-shape has Area 24. Look for a polygon with Area approx 24.
    # Note: user might have 2 separate rectangles (Area 16 + 8 or 12 + 12).
    # Or 1 main polygon (Area 24).
    found_main_poly = False
    found_sub_polys = 0
    total_area = 0
    
    for poly in polygons:
        area = poly.get("value", 0)
        total_area += area
        if abs(area - 24.0) < 0.5:
            found_main_poly = True
    
    if found_main_poly:
        score += 20
        feedback.append("L-shaped polygon found (Area=24).")
    elif abs(total_area - 24.0) < 0.5 and len(polygons) >= 2:
        score += 20
        feedback.append("Composite polygons found summing to Area 24.")
    else:
        feedback.append(f"Polygon area mismatch. Found total: {total_area}, expected 24.")

    # 3. Decomposition Centroids (20 pts)
    # Check for points near expected sub-centroids
    # Set 1: (1,4) and (4,1)
    # Set 2: (1,5) and (3,1)
    def find_point_near(target, point_list):
        for p in point_list:
            if math.hypot(p['x']-target[0], p['y']-target[1]) < tolerance:
                return True
        return False

    set1_found = find_point_near(sub_c1[0], points) and find_point_near(sub_c1[1], points)
    set2_found = find_point_near(sub_c2[0], points) and find_point_near(sub_c2[1], points)

    if set1_found or set2_found:
        score += 20
        feedback.append("Decomposition centroids marked correctly.")
    else:
        # Check partial
        count = 0
        for target in sub_c1 + sub_c2:
            if find_point_near(target, points):
                count += 1
        if count > 0:
            score += 10
            feedback.append("Partial decomposition points found.")
        else:
            feedback.append("Decomposition centroids missing.")

    # 4. Global Centroid G (30 pts)
    if find_point_near(expected_G, points):
        score += 30
        feedback.append(f"Global Centroid G found at {expected_G}.")
    else:
        feedback.append("Global Centroid G (2,3) not found.")

    # 5. Suspension Line and Angle (20 pts)
    # Check for angle near 21.8 deg
    angle_found = False
    for ang in angles:
        # GeoGebra might measure the reflex angle or the supplementary one
        deg = ang.get("degrees", 0)
        # 21.8, 360-21.8=338.2, etc.
        if abs(deg - expected_angle) < 1.0 or abs(deg - (360-expected_angle)) < 1.0:
            angle_found = True
            break
            
    # Check for line through (0,8) and (2,3)
    # Line eq: y - 8 = m(x - 0) -> y - 8 = -2.5x -> 2.5x + y - 8 = 0
    # Or in ax + by + c = 0 form: 5x + 2y - 16 = 0
    line_found = False
    for ln in lines:
        a, b, c = ln['a'], ln['b'], ln['c']
        # Normalize
        mag = math.hypot(a, b)
        if mag == 0: continue
        a, b, c = a/mag, b/mag, c/mag
        
        # Expected: 5x + 2y - 16 = 0
        # Norm: 5/sqrt(29) ~ 0.928, 2/sqrt(29) ~ 0.371, -16/sqrt(29) ~ -2.97
        exp_a, exp_b, exp_c = 5.0, 2.0, -16.0
        exp_mag = math.hypot(exp_a, exp_b)
        exp_a, exp_b, exp_c = exp_a/exp_mag, exp_b/exp_mag, exp_c/exp_mag
        
        # Check alignment (direction can be flipped)
        dot = a*exp_a + b*exp_b
        if abs(abs(dot) - 1.0) < 0.01: # Parallel
            # Check C
            if abs(abs(c) - abs(exp_c)) < 0.1:
                line_found = True
                break

    if angle_found and line_found:
        score += 20
        feedback.append("Suspension line and angle correct.")
    elif angle_found:
        score += 15
        feedback.append("Angle correct, but suspension line object not identified.")
    elif line_found:
        score += 10
        feedback.append("Suspension line correct, angle missing.")
    else:
        feedback.append("Suspension physics visualization missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }