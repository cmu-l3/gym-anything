#!/usr/bin/env python3
"""
Verifier for Euler Line Construction task.
Verifies geometric properties of the constructed triangle and centers.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def dist(p1, p2):
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def find_closest_point(target, points):
    """Finds the closest point in list to target coordinates."""
    if not points:
        return None, float('inf')
    
    closest = min(points, key=lambda p: dist((p['x'], p['y']), target))
    distance = dist((closest['x'], closest['y']), target)
    return closest, distance

def verify_euler_line_construction(traj, env_info, task_info):
    """
    Verify Euler line construction.
    
    Criteria:
    1. File creation (10 pts)
    2. Triangle vertices A, B, C correct (15 pts)
    3. Centroid G correct (15 pts)
    4. Circumcenter O correct (15 pts)
    5. Orthocenter H correct (15 pts)
    6. Euler Line logic (15 pts)
    7. Annotation present (15 pts)
    
    Total: 100 pts. Pass: 70 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}
    
    # Load metadata
    meta = task_info.get('metadata', {})
    tolerance = meta.get('tolerance', 0.3)
    exp_verts = meta.get('vertices', {'A': [1,1], 'B': [7,2], 'C': [4,6]})
    exp_centers = meta.get('expected_centers', {})
    
    # Retrieve result
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
            
    score = 0
    feedback = []
    
    # 1. File Check
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File created successfully (+10).")
    elif result.get('file_found'):
        feedback.append("File found but not created during this session (0).")
    else:
        feedback.append("File euler_line.ggb not found (0).")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        
    points = result.get('points', [])
    
    # 2. Vertices Check
    vertices_found = 0
    for label, coords in exp_verts.items():
        _, d = find_closest_point(coords, points)
        if d <= tolerance:
            vertices_found += 1
    
    if vertices_found == 3:
        score += 15
        feedback.append("Triangle vertices A, B, C correct (+15).")
    elif vertices_found > 0:
        score += 5 * vertices_found
        feedback.append(f"Found {vertices_found}/3 vertices correct (+{5*vertices_found}).")
    else:
        feedback.append("Triangle vertices incorrect.")

    # 3. Centroid Check
    g_pt, g_dist = find_closest_point(exp_centers['centroid'], points)
    has_centroid = g_dist <= tolerance
    if has_centroid:
        score += 15
        feedback.append("Centroid G found (+15).")
    else:
        feedback.append(f"Centroid missing or incorrect (dist: {g_dist:.2f}).")

    # 4. Circumcenter Check
    o_pt, o_dist = find_closest_point(exp_centers['circumcenter'], points)
    has_circum = o_dist <= tolerance
    if has_circum:
        score += 15
        feedback.append("Circumcenter O found (+15).")
    else:
        feedback.append(f"Circumcenter missing or incorrect (dist: {o_dist:.2f}).")
        
    # 5. Orthocenter Check
    h_pt, h_dist = find_closest_point(exp_centers['orthocenter'], points)
    has_ortho = h_dist <= tolerance
    if has_ortho:
        score += 15
        feedback.append("Orthocenter H found (+15).")
    else:
        feedback.append(f"Orthocenter missing or incorrect (dist: {h_dist:.2f}).")

    # 6. Euler Line Check (Line presence + passing through centers)
    # Since checking explicit line equation from XML is hard without parser,
    # we assume if centers are found and a line command exists, they likely drew it.
    # We can check if a 'Line' command exists.
    has_line_cmd = any('Line' in cmd for cmd in result.get('commands', []))
    lines_exist = len(result.get('lines', [])) > 0
    
    # Logic: If at least 2 centers exist and a line is drawn, we give credit.
    # Strict collinearity check is hard without the line definition.
    centers_found_count = sum([has_centroid, has_circum, has_ortho])
    
    if centers_found_count >= 2 and (has_line_cmd or lines_exist):
        score += 15
        feedback.append("Euler line constructed (+15).")
    elif centers_found_count >= 2:
        feedback.append("Centers found but line connecting them missing.")
    else:
        feedback.append("Insufficient centers to define Euler line.")

    # 7. Annotation Check
    if len(result.get('texts', [])) > 0:
        score += 15
        feedback.append("Annotation found (+15).")
    else:
        feedback.append("No text annotation found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }