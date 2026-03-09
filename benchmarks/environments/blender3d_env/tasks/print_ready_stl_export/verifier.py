#!/usr/bin/env python3
"""
Verifier for print_ready_stl_export task.

Criteria:
1. STL file exists and was created during task.
2. Geometry Dimensions:
   - Z height should be approx 65 units (60mm head + 5mm base).
   - X/Y width should be approx 40 units (base diameter) or slightly larger for Suzanne's ears.
     (Suzanne is wider than it is tall usually, but base is 40mm.
      Suzanne default is ~2.7 wide. Scaled to 60mm height (x30 factor approx), width becomes ~80mm.
      Wait, let's re-calculate:
      Default Suzanne: ~2m tall (Z).
      Target Z: 60mm.
      If base units are mm, 60 units high.
      Width will be proportional.
      The Base Cylinder is 40mm diameter.
      So max width should be max(SuzanneWidth, 40).
      Suzanne (2.7 units X) scaled to 60mm height (approx 2.0 units Z) -> Scale factor ~30.
      Width ~ 2.7 * 30 = 81mm.
      So X dimension should be around 80-90mm.)

   - Crucially, checks for magnitude 60-70, NOT 0.06 (meters).
3. Single Mesh: The file should contain one combined mesh (or at least valid geometry).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_ready_stl(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Checks (20 pts)
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "No STL file found at expected path."}
    
    score += 10
    if result.get("created_during_task"):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it wasn't modified during task.")

    # 2. Geometry Checks (80 pts)
    geo = result.get("geometry", {})
    if not geo.get("valid_geometry"):
        feedback.append("STL file could not be imported or contains no geometry.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    dims = geo.get("dimensions", [0, 0, 0])
    x, y, z = dims[0], dims[1], dims[2]
    
    # Target: Z ~ 65mm (60 Suzanne + 5 Base)
    # Tolerance: +/- 5mm (Agent might overlap them slightly differently or measure Suzanne differently)
    target_z = 65.0
    tol_z = 5.0
    
    # Target: Base is 40mm. Suzanne ears might stick out further.
    # Suzanne aspect ratio (approx): X ~ 1.4 * Z.
    # If Z=60, X ~ 84.
    # So max dimension should be around 80-90.
    
    # Check Units/Scale (The most important part of this task)
    if 50.0 < z < 80.0:
        score += 40
        feedback.append(f"Z-Height correct ({z:.1f}mm).")
    elif 0.05 < z < 0.08:
        feedback.append(f"Z-Height is {z:.3f} units. Looks like Meters (0.065m) instead of Millimeters (65mm). Task required 1 unit = 1 mm.")
        # Partial credit for correct shape but wrong scale
        score += 10 
    else:
        feedback.append(f"Z-Height incorrect ({z:.1f}). Expected ~65.")

    # Check Base/Width presence
    # If base is present, min width is 40.
    if max(x, y) > 35.0:
        score += 20
        feedback.append(f"Width/Depth consistent with required dimensions ({max(x,y):.1f}mm).")
    else:
        feedback.append(f"Model seems too narrow ({max(x,y):.1f}mm). Did you add the 40mm base?")

    # Check for combination (One object in file, or joined geometry)
    # The export script joins everything on import, so we verify vertex count is substantial
    # Suzanne ~ 500 verts. Cylinder ~ 32-64 verts.
    # Boolean union might increase count.
    if geo.get("vertex_count", 0) > 400:
        score += 20
        feedback.append("Geometry complexity looks correct.")
    else:
        feedback.append("Mesh seems too simple (vertex count low).")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }