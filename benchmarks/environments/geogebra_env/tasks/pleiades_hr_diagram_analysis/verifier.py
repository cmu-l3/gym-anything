#!/usr/bin/env python3
import json
import logging
import tempfile
import os
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pleiades_hr_diagram_analysis(traj, env_info, task_info):
    """
    Verifies the Pleiades HR Diagram Analysis task.
    Checks:
    1. File creation/modification.
    2. Presence of data points matching the physics: Y = -(m - 5.6) = 5.6 - m.
    3. Annotation (Polygon and Text).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_data = metadata.get('data_points_source', [])
    tolerance = metadata.get('tolerance', 0.15)
    distance_modulus = metadata.get('distance_modulus', 5.6)

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Check (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File 'pleiades_analysis.ggb' created successfully.")
    elif result.get('file_found'):
        score += 5
        feedback.append("File found, but timestamp check failed (pre-existing?).")
    else:
        feedback.append("File 'pleiades_analysis.ggb' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Data Point Verification (60 pts)
    # Logic: The user should plot x = B-V, y = -(m - 5.6) = 5.6 - m
    points_found = result.get('points_found', [])
    
    if len(points_found) < 5:
        feedback.append(f"Only {len(points_found)} points found. Expected at least 5.")
    else:
        feedback.append(f"Found {len(points_found)} points.")

    matches = 0
    # We verify against the subset of stars provided in metadata
    # The agent doesn't need to plot *only* these, but *at least* these (or most of them) should be present
    # derived from the full CSV.
    
    # Let's perform a generic check: For every expected star, is there a point nearby?
    valid_transformations = 0
    
    for star in expected_data:
        bv = star['bv']
        m = star['m']
        
        # Expected coordinates
        target_x = bv
        target_y = distance_modulus - m  # y = -(m - 5.6) = 5.6 - m
        
        # Look for a match
        found_match = False
        for p in points_found:
            dx = abs(p['x'] - target_x)
            dy = abs(p['y'] - target_y)
            if dx <= tolerance and dy <= tolerance:
                found_match = True
                break
        
        if found_match:
            valid_transformations += 1
    
    # Score calculation for data
    # If we find matches for at least 3 of the 5 sample stars, we assume the formula was correct.
    if valid_transformations >= 3:
        score += 60
        feedback.append(f"Data verification passed: {valid_transformations}/{len(expected_data)} key stars matched expected coordinates (Y = 5.6 - m).")
    elif valid_transformations >= 1:
        score += 20
        feedback.append(f"Data verification partial: {valid_transformations}/{len(expected_data)} stars matched. Check formula signs.")
    else:
        feedback.append("Data verification failed. No points matched the expected coordinates (x=B-V, y=-(m-5.6)). Did you calculate Absolute Magnitude correctly?")

    # 3. Annotation Verification (30 pts)
    # Polygon (15 pts)
    if result.get('polygon_found'):
        score += 15
        feedback.append("Main Sequence polygon annotation found.")
    else:
        feedback.append("Polygon annotation missing.")

    # Text (15 pts)
    if result.get('main_sequence_text_found'):
        score += 15
        feedback.append("'Main Sequence' text label found.")
    elif result.get('text_found'):
        score += 5
        feedback.append("Text label found, but didn't explicitly match 'Main Sequence'.")
    else:
        feedback.append("Text label missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }