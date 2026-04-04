#!/usr/bin/env python3
"""
Verifier for model_naca_airfoil task.

Metric Targets:
- File exists and created during task.
- Valid 3D Solid found.
- Bounding Box X (Chord) ~= 100mm.
- Bounding Box Z (Span) ~= 200mm.
- Bounding Box Y (Thickness) ~= 12mm (NACA 2412 is 12% thick).
- Volume ~= Area * Span.
  Area of NACA 2412 with Chord 100 is approx 820 mm^2.
  Volume = 820 * 200 = 164,000 mm^3.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_naca_airfoil(traj, env_info, task_info):
    """
    Verify the created wing model based on geometric properties extracted from the environment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: Copy function not available"}

    # Targets
    TARGET_CHORD = 100.0
    TARGET_SPAN = 200.0
    TARGET_THICKNESS = 12.0 # 12% of 100
    TARGET_VOLUME = 164000.0 # Approx 820 * 200
    
    TOLERANCE_MM = 2.0 # Allow slight bounding box deviations
    TOLERANCE_VOL = 0.10 # 10% volume tolerance (meshing/spline variations)

    score = 0
    feedback_parts = []
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. File Existence & Anti-Gaming (15 pts)
    if result.get('output_exists'):
        if result.get('file_created_during_task'):
            score += 15
            feedback_parts.append("File created successfully")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp is old (reused file?)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Geometry Analysis (85 pts)
    geo = result.get('geometry', {})
    
    if not geo.get('valid_file'):
        return {"passed": False, "score": score, "feedback": "File is not a valid FreeCAD document"}

    # Check for solid (20 pts)
    if geo.get('has_solid'):
        score += 20
        feedback_parts.append("Valid solid geometry found")
    else:
        feedback_parts.append("No solid object found (only wire/mesh?)")
        # Proceed with checks but penalties apply

    # Check Span (Z-length) - CRITICAL (25 pts)
    z_len = geo.get('bbox_z', 0)
    if abs(z_len - TARGET_SPAN) < TOLERANCE_MM:
        score += 25
        feedback_parts.append(f"Span correct ({z_len:.1f}mm)")
    elif abs(z_len - TARGET_SPAN) < 10.0:
        score += 10
        feedback_parts.append(f"Span incorrect but close ({z_len:.1f}mm)")
    else:
        feedback_parts.append(f"Span wrong ({z_len:.1f}mm, expected 200)")

    # Check Chord (X-length) (15 pts)
    x_len = geo.get('bbox_x', 0)
    if abs(x_len - TARGET_CHORD) < TOLERANCE_MM:
        score += 15
        feedback_parts.append(f"Chord correct ({x_len:.1f}mm)")
    else:
        feedback_parts.append(f"Chord wrong ({x_len:.1f}mm, expected 100)")

    # Check Shape Profile (Thickness Ratio) (10 pts)
    # This verifies they actually used the airfoil data, not just a block
    y_len = geo.get('bbox_y', 0)
    if x_len > 0:
        ratio = y_len / x_len
        # NACA 2412 is ~12% thick. Allow 11-13%
        if 0.11 <= ratio <= 0.13:
            score += 10
            feedback_parts.append(f"Airfoil thickness ratio correct ({ratio:.3f})")
        else:
            feedback_parts.append(f"Wrong profile shape (Thickness ratio: {ratio:.3f})")

    # Check Volume (15 pts)
    vol = geo.get('volume', 0)
    if vol > 0:
        vol_error = abs(vol - TARGET_VOLUME) / TARGET_VOLUME
        if vol_error < TOLERANCE_VOL:
            score += 15
            feedback_parts.append(f"Volume correct ({vol:.0f} mm3)")
        elif vol_error < 0.25: # 25% tolerance partial credit
            score += 5
            feedback_parts.append(f"Volume rough match ({vol:.0f} mm3)")
        else:
            feedback_parts.append(f"Volume mismatch ({vol:.0f} vs {TARGET_VOLUME:.0f})")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }