#!/usr/bin/env python3
"""
Verifier for generate_density_graded_fea_model task.

Scoring Breakdown (100 pts):
1. Project file exists & created during task: 10 pts
2. Exactly 3 masks created: 20 pts
3. Mask thresholds match Low/Med/High specifications: 30 pts
4. Exactly 3 surfaces created: 20 pts
5. Surface colors match (Low=Blue, Med=Green, High=Red): 20 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_density_graded_fea_model(traj, env_info, task_info):
    """Verify density graded FEA model generation."""
    
    # 1. Setup and retrieve result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Define targets
    # Threshold targets (min, max)
    TARGET_LOW = (226, 600)
    TARGET_MED = (601, 1200)
    TARGET_HIGH = (1201, 3071) 
    TOLERANCE = task_info.get("metadata", {}).get("threshold_tolerance", 15)

    # 2. Verify File Existence (10 pts)
    if result.get("file_exists") and result.get("created_during_task"):
        score += 10
        feedback.append("Project file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Project file not found or not created during task."}

    # 3. Verify Masks (20 pts for count, 30 pts for thresholds)
    masks = result.get("masks", [])
    if len(masks) == 3:
        score += 20
        feedback.append("Correct number of masks (3).")
    else:
        feedback.append(f"Incorrect number of masks: {len(masks)} (expected 3).")
        # Partial credit if they made some masks? No, strictly 3 for FEA model.

    # Check thresholds
    low_found = False
    med_found = False
    high_found = False

    for m in masks:
        t_min, t_max = m.get("threshold_range", [0,0])
        
        # Check Low
        if abs(t_min - TARGET_LOW[0]) <= TOLERANCE and abs(t_max - TARGET_LOW[1]) <= TOLERANCE:
            low_found = True
        # Check Medium
        elif abs(t_min - TARGET_MED[0]) <= TOLERANCE and abs(t_max - TARGET_MED[1]) <= TOLERANCE:
            med_found = True
        # Check High (Max can be variable depending on dataset max or preset, allow leeway on upper bound)
        elif abs(t_min - TARGET_HIGH[0]) <= TOLERANCE and t_max >= 1500:
            high_found = True

    if low_found and med_found and high_found:
        score += 30
        feedback.append("All density thresholds configured correctly.")
    else:
        missing = []
        if not low_found: missing.append("Low(226-600)")
        if not med_found: missing.append("Med(601-1200)")
        if not high_found: missing.append("High(1201+)")
        feedback.append(f"Missing or incorrect threshold ranges: {', '.join(missing)}.")
        # Partial credit: 10 pts per correct mask
        if low_found: score += 10
        if med_found: score += 10
        if high_found: score += 10

    # 4. Verify Surfaces (20 pts for count)
    surfaces = result.get("surfaces", [])
    if len(surfaces) == 3:
        score += 20
        feedback.append("Correct number of 3D surfaces (3).")
    else:
        feedback.append(f"Incorrect number of surfaces: {len(surfaces)} (expected 3).")
        if len(surfaces) > 0: score += 5 # Small consolation

    # 5. Verify Colors (20 pts)
    # Strategy: Match surface to density logic implicitly or check for distinct R, G, B surfaces
    # Since we can't easily link surface X to mask Y without deep parsing of refs (which might be complex),
    # we will check if the SET of surfaces contains one Red-dominant, one Green-dominant, one Blue-dominant.
    
    has_blue = False
    has_green = False
    has_red = False

    for s in surfaces:
        r, g, b = s.get("color", [0,0,0])
        # InVesalius uses 0.0-1.0 floats
        
        # Blue dominant: B > R and B > G
        if b > r and b > g and b > 0.5: has_blue = True
        # Green dominant: G > R and G > B
        if g > r and g > b and g > 0.5: has_green = True
        # Red dominant: R > G and R > B
        if r > g and r > b and r > 0.5: has_red = True

    color_score = 0
    if has_blue: color_score += 6
    if has_green: color_score += 7
    if has_red: color_score += 7
    
    score += color_score
    if color_score == 20:
        feedback.append("Surface color coding correct (Red/Green/Blue).")
    else:
        feedback.append(f"Color coding incomplete. Found Red:{has_red}, Green:{has_green}, Blue:{has_blue}.")

    # Final Pass check
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }