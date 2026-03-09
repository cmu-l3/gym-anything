#!/usr/bin/env python3
import json
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_distance(p1, p2):
    """Euclidean distance for simple lat/lon check."""
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_digitize_connected_route_snapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    expected_pts = metadata.get('expected_vertices', [])
    tolerance = metadata.get('snapping_tolerance_degrees', 1e-5)

    score = 0
    feedback = []

    # 1. Output existence (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("Output file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Created during task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")

    # 3. Valid Geometry Analysis
    analysis = result.get('geometry_analysis', {})
    
    if analysis.get('valid_layer'):
        score += 10
        feedback.append("Valid vector layer.")
    else:
        return {"passed": False, "score": score, "feedback": "File is not a valid vector layer."}

    # 4. Feature Count (10 pts)
    f_count = analysis.get('feature_count', 0)
    if f_count == 1:
        score += 10
        feedback.append("Correct feature count (1).")
    else:
        feedback.append(f"Incorrect feature count: {f_count} (expected 1).")

    # 5. Geometry Type (10 pts)
    g_type = analysis.get('geom_type', 'Unknown')
    if g_type == 'LineString':
        score += 10
        feedback.append("Correct geometry type (LineString).")
    else:
        feedback.append(f"Incorrect geometry type: {g_type}.")

    # 6. Snapping Verification (50 pts total)
    # We expect 3 vertices matching A, B, C
    coords = analysis.get('coordinates', [])
    
    if len(coords) < 3:
        feedback.append(f"Line has too few vertices: {len(coords)} (expected 3).")
        # Fail immediately on snapping if not enough points
    else:
        # Check first vertex (Point A)
        d1 = calculate_distance(coords[0], expected_pts[0])
        if d1 < tolerance:
            score += 15
            feedback.append("Start point snapped correctly.")
        else:
            feedback.append(f"Start point missed by {d1:.6f} degrees.")

        # Check last vertex (Point C)
        d3 = calculate_distance(coords[-1], expected_pts[2])
        if d3 < tolerance:
            score += 15
            feedback.append("End point snapped correctly.")
        else:
            feedback.append(f"End point missed by {d3:.6f} degrees.")

        # Check middle vertex (Point B)
        # Find the vertex in coords that is closest to expected Point B
        # This handles cases where agent might have added extra vertices
        min_d2 = min([calculate_distance(c, expected_pts[1]) for c in coords])
        
        if min_d2 < tolerance:
            score += 20
            feedback.append("Middle point snapped correctly.")
        else:
            feedback.append(f"Middle point missed by {min_d2:.6f} degrees.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }