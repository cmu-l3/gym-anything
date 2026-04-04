#!/usr/bin/env python3
"""
Verifier for design_radial_impeller task.

Logic:
1. Checks if file was created/modified during task.
2. Reads geometric analysis report generated inside the container.
3. Verifies Volume, Bounding Box, and Feature usage (PolarPattern).
4. Uses VLM (via trajectory) to verify workflow if programmatic checks are borderline.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_radial_impeller(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_volume = metadata.get('expected_volume_mm3', 17900)
    vol_tolerance = metadata.get('volume_tolerance_percent', 10) / 100.0
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Anti-Gaming (20 pts)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Impeller file not found at expected path."}
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp predates task start.")
        score += 5 # Minimal points if file exists but old
    else:
        score += 20
        feedback_parts.append("File created successfully.")

    # 2. Geometry Analysis (80 pts)
    geo = result.get('geometry_analysis', {})
    if not geo.get('valid_document', False):
         return {"passed": False, "score": score, "feedback": "File created but is not a valid FreeCAD document."}

    # Volume Check (30 pts)
    volume = geo.get('volume', 0)
    # Calculate limits
    min_vol = expected_volume * (1 - vol_tolerance)
    max_vol = expected_volume * (1 + vol_tolerance)
    
    if min_vol <= volume <= max_vol:
        score += 30
        feedback_parts.append(f"Volume correct ({volume:.0f} mm³).")
    elif volume > 0:
        # Partial credit if somewhat close (within 50%)
        if expected_volume * 0.5 <= volume <= expected_volume * 1.5:
            score += 10
            feedback_parts.append(f"Volume mismatch ({volume:.0f} vs {expected_volume}), check dimensions.")
        else:
            feedback_parts.append(f"Volume incorrect ({volume:.0f} mm³).")
    else:
        feedback_parts.append("Solid has zero volume.")

    # Pattern Feature Check (20 pts)
    features = geo.get('features', [])
    pattern_found = False
    pattern_count_correct = False
    
    # Check explicitly for PolarPattern object type
    for feat in features:
        if "PolarPattern" in feat.get('type', '') or "PolarPattern" in feat.get('name', ''):
            pattern_found = True
            break
            
    if pattern_found:
        score += 10
        feedback_parts.append("Polar Pattern feature detected.")
        if geo.get('polar_pattern_count', 0) == 6:
            score += 10
            feedback_parts.append("Pattern count (6) correct.")
        else:
            feedback_parts.append(f"Pattern count mismatch (found {geo.get('polar_pattern_count')}).")
    else:
        feedback_parts.append("Polar Pattern not detected. Did you model blades individually?")

    # Dimensions / Bounding Box Check (15 pts)
    # Expected: ~60 x 60 x 15 mm
    bbox = geo.get('bbox', [0,0,0]) # [x, y, z]
    # Check diameter (X/Y should be close to 60)
    xy_ok = (58 <= bbox[0] <= 62) and (58 <= bbox[1] <= 62)
    # Check height (Z should be close to 15)
    z_ok = (14 <= bbox[2] <= 16)
    
    if xy_ok and z_ok:
        score += 15
        feedback_parts.append("Overall dimensions correct.")
    elif z_ok:
        score += 5
        feedback_parts.append("Height correct, diameter incorrect.")
    elif xy_ok:
        score += 5
        feedback_parts.append("Diameter correct, height incorrect.")
    else:
        feedback_parts.append(f"Dimensions incorrect (approx {bbox[0]:.1f}x{bbox[1]:.1f}x{bbox[2]:.1f}).")

    # Center of Mass (Symmetry Check) (15 pts)
    # Since it's a radial impeller centered at origin, CoM X and Y should be very close to 0
    com = geo.get('center_of_mass', [100, 100, 100])
    if abs(com[0]) < 0.5 and abs(com[1]) < 0.5:
        score += 15
        feedback_parts.append("Symmetry confirmed (Center of Mass at origin).")
    else:
        feedback_parts.append("Model is not symmetric or not centered.")

    # Pass logic
    passed = (score >= 70) and pattern_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }