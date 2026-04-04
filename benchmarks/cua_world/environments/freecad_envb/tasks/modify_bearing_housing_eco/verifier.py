#!/usr/bin/env python3
"""
Verifier for modify_bearing_housing_eco task.

Verification Strategy:
1. File Existence: Check if modified_housing.FCStd exists.
2. Anti-Gaming: Check timestamps and ensure file content changed (hash check).
3. Geometry Analysis (Primary):
   - The export_result.sh script runs a headless FreeCAD script inside the container.
   - It extracts the bounding box and list of all cylindrical face diameters.
   - We verify that a 16.0mm hole and multiple 5.5mm holes exist.
   - We verify the bounding box hasn't changed significantly (preserving the part).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_housing(traj, env_info, task_info):
    """
    Verify the bearing housing modification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    target_bore = metadata.get('target_bore_diameter', 16.0)
    target_mount = metadata.get('target_mount_diameter', 5.5)
    tol = metadata.get('diameter_tolerance', 0.1)
    
    # --------------------------------------------------------------
    # 1. Retrieve Result JSON
    # --------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------
    # 2. Basic File Checks (20 points)
    # --------------------------------------------------------------
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file modified_housing.FCStd not found."}
    
    score += 5
    
    if not result.get('file_modified_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it was not modified during task.")
    else:
        score += 5

    if not result.get('hash_changed', False):
        return {"passed": False, "score": score, "feedback": "File is identical to the original input. No changes detected."}
    
    score += 10 # File exists and is different from input
    
    # --------------------------------------------------------------
    # 3. Geometry Analysis (80 points)
    # --------------------------------------------------------------
    geo = result.get('geometry_analysis', {})
    if not geo.get('success', False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Failed to analyze geometry: {geo.get('error', 'Unknown error')}"
        }

    # A. Bounding Box Check (Ensure they didn't delete the part or make a new random one)
    # Original T8 bracket is approx 46 x 40 x 37 mm (roughly)
    # We just check if it's "reasonable" - i.e., not 0 and not massive
    bbox = geo.get('bbox', [0, 0, 0])
    volume = geo.get('volume', 0)
    
    if volume < 1000:
        feedback_parts.append("Part volume is too small (part deleted?).")
    elif max(bbox) < 10 or max(bbox) > 500:
        feedback_parts.append(f"Part dimensions unreasonable: {bbox}")
    else:
        score += 10 # Preserved geometry
    
    # B. Bore Check (16.0 mm)
    cyl_diameters = geo.get('cylindrical_faces', [])
    
    # Find matches
    found_bore = False
    found_mounts = 0
    
    for d in cyl_diameters:
        # Check Central Bore
        if abs(d - target_bore) <= tol:
            found_bore = True
        
        # Check Mounting Holes
        if abs(d - target_mount) <= tol:
            found_mounts += 1
            
    # Score Bore
    if found_bore:
        score += 35
        feedback_parts.append(f"SUCCESS: Central bore found at {target_bore}mm.")
    else:
        # Check if they left it at original (approx 10mm or 22mm depending on feature)
        feedback_parts.append(f"FAILED: Central bore of {target_bore}mm not found. Found diameters: {cyl_diameters}")

    # Score Mounting Holes (Need at least 4 faces - usually holes have 1 or 2 faces each)
    # The verifier in export script returns faces. A through hole might have 1 or 2 cylindrical faces.
    # We expect at least 4 faces matching the dimension.
    if found_mounts >= 4:
        score += 35
        feedback_parts.append(f"SUCCESS: Mounting holes found at {target_mount}mm.")
    elif found_mounts > 0:
        score += 15
        feedback_parts.append(f"PARTIAL: Only {found_mounts} mounting hole faces found (expected 4+).")
    else:
        feedback_parts.append(f"FAILED: No mounting holes of {target_mount}mm found.")

    # --------------------------------------------------------------
    # 4. Final Verification
    # --------------------------------------------------------------
    passed = score >= 80  # Requires file + bore + mounts basically
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }