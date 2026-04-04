#!/usr/bin/env python3
"""
Verifier for Mars Elliptical Orbit task.

Verifies:
1. File creation timestamp (Anti-gaming)
2. Sun position (0,0)
3. Mars orbit parameters (Semi-major axis ~1.524, second focus position)
4. Earth orbit (Circle radius ~1)
5. Labels/Annotations
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mars_elliptical_orbit_kepler(traj, env_info, task_info):
    """
    Verify the Mars orbit construction.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    metadata = task_info.get('metadata', {})
    # Expected values
    EXP_A = metadata.get('mars_a', 1.524)
    EXP_E = metadata.get('mars_e', 0.0934)
    EXP_C = EXP_A * EXP_E  # approx 0.1423
    
    # Tolerances
    TOL_COORD = metadata.get('tolerance_coords', 0.1)
    TOL_DIST = metadata.get('tolerance_dist', 0.15)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify File Creation (15 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 15
        feedback.append("File 'mars_orbit.ggb' created successfully.")
    else:
        feedback.append("File not found or not created during task window.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    points = result.get('points', [])
    conics = result.get('conics', [])
    commands = result.get('commands', [])
    texts = result.get('texts', [])

    # 3. Verify Sun Position (15 pts)
    # Look for point near (0,0)
    sun_found = False
    for p in points:
        dist = math.sqrt(p['x']**2 + p['y']**2)
        if dist < TOL_COORD:
            sun_found = True
            break
    
    if sun_found:
        score += 15
        feedback.append("Sun found at origin.")
    else:
        feedback.append("Sun point (0,0) not found.")

    # 4. Verify Mars Orbit Construction (20 pts)
    # We look for a focus at (2*c, 0) or (-2*c, 0) relative to Sun, or a valid Ellipse command
    # Mars F2 should be at dist ~0.2846 from Sun if F1 is Sun
    # Or simply check if 'Ellipse' command was used and we have points
    
    has_ellipse_cmd = "Ellipse" in commands
    
    # Check for second focus point
    # Distance between foci = 2*c = 2 * 1.524 * 0.0934 = 0.2846
    f2_found = False
    for p in points:
        # Distance from origin
        d = math.sqrt(p['x']**2 + p['y']**2)
        # Check if it's roughly 2*c (0.284)
        if abs(d - (2 * EXP_C)) < TOL_COORD:
            f2_found = True
            break

    if has_ellipse_cmd and (f2_found or len(conics) >= 2):
        score += 20
        feedback.append("Mars elliptical orbit constructed.")
    elif has_ellipse_cmd:
        score += 10
        feedback.append("Ellipse command used, but second focus placement unclear.")
    else:
        feedback.append("Mars orbit (Ellipse) not found.")

    # 5. Verify Earth Orbit (15 pts)
    # Circle command or conic with radius 1
    has_circle_cmd = "Circle" in commands
    # Or check if any point is at distance 1.0 (some users construct it via point)
    point_at_1 = any(abs(math.sqrt(p['x']**2 + p['y']**2) - 1.0) < TOL_COORD for p in points)
    
    if has_circle_cmd or (point_at_1 and len(conics) >= 2):
        score += 15
        feedback.append("Earth orbit (Circle) found.")
    else:
        feedback.append("Earth orbit not clearly defined.")

    # 6. Verify Perihelion/Aphelion (15 pts)
    # Perihelion dist = a(1-e) = 1.3816
    # Aphelion dist = a(1+e) = 1.6663
    peri_found = False
    aph_found = False
    
    for p in points:
        d = math.sqrt(p['x']**2 + p['y']**2)
        if abs(d - 1.3816) < TOL_DIST:
            peri_found = True
        if abs(d - 1.6663) < TOL_DIST:
            aph_found = True
            
    if peri_found and aph_found:
        score += 15
        feedback.append("Perihelion and Aphelion points identified.")
    elif peri_found or aph_found:
        score += 7
        feedback.append("One of Perihelion/Aphelion identified.")
    else:
        feedback.append("Perihelion/Aphelion points not found at correct distances.")

    # 7. Verify Text Annotation (20 pts)
    # Check for "eccentricity" or "0.0934" in texts
    text_content = " ".join(texts).lower()
    if "0.09" in text_content or "eccentricity" in text_content:
        score += 20
        feedback.append("Eccentricity label found.")
    elif len(texts) > 0:
        score += 10
        feedback.append("Text labels found, but specific value check ambiguous.")
    else:
        feedback.append("No text annotations found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }