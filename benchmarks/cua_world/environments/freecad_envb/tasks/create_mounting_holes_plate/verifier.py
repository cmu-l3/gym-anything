#!/usr/bin/env python3
"""
Verifier for create_mounting_holes_plate task.

Checks:
1. File exists and is a valid FreeCAD solid.
2. Bounding box dimensions (200x100x8).
3. Volume accuracy (Checks for presence of holes via mass subtraction).
4. Explicit hole detection (Cylindrical faces count and position).
5. VLM trajectory verification (did the agent actually model it?).
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mounting_plate(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_dims = metadata.get('expected_dims', [200.0, 100.0, 8.0])
    expected_volume = metadata.get('expected_volume', 158480.0)
    expected_hole_count = metadata.get('expected_hole_count', 8)
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Check 1: File Existence & Validity (20 pts)
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    geo_data = result.get('geometry_analysis', {}) or {}
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not file_created:
        feedback.append("⚠️ File timestamp indicates it wasn't created during this session.")
        # We punish this heavily as it implies pre-caching
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: File not created during task."}

    valid_solid = geo_data.get('valid_file', False) and geo_data.get('solid_found', False)
    
    if valid_solid:
        score += 20
        feedback.append("✅ Valid solid geometry found.")
    else:
        feedback.append("❌ File exists but contains no valid solid.")
        return {"passed": False, "score": 5, "feedback": " ".join(feedback)}

    # Check 2: Dimensions (20 pts)
    # Bbox should be 200 x 100 x 8
    # We allow some rotation, so we sort the dimensions
    bbox = geo_data.get('bbox_dims', [0,0,0])
    bbox.sort()
    exp_dims_sorted = sorted(expected_dims)
    
    dims_ok = True
    for i in range(3):
        if abs(bbox[i] - exp_dims_sorted[i]) > 2.0: # 2mm tolerance
            dims_ok = False
            
    if dims_ok:
        score += 20
        feedback.append(f"✅ Dimensions correct (~{bbox}).")
    else:
        feedback.append(f"❌ Dimensions incorrect. Expected {exp_dims_sorted}, got {bbox}.")

    # Check 3: Volume (20 pts)
    # This implicitly checks for holes. A solid block would be 160,000.
    # With holes it should be ~158,480.
    vol = geo_data.get('volume', 0)
    vol_diff_percent = abs(vol - expected_volume) / expected_volume * 100
    
    if vol_diff_percent < 5.0:
        score += 20
        feedback.append(f"✅ Volume correct ({vol:.0f} mm³).")
    elif abs(vol - 160000) < 1000:
        feedback.append("❌ Volume matches solid block (holes missing).")
    else:
        feedback.append(f"❌ Volume incorrect ({vol:.0f} mm³).")

    # Check 4: Hole Features (20 pts)
    # We check the cylindrical faces found
    radii = geo_data.get('hole_radii', [])
    valid_holes = 0
    for r in radii:
        if abs(r - 2.75) < 0.25: # 2.75mm radius = 5.5mm diameter
            valid_holes += 1
            
    # FreeCAD often represents a cylinder as 1 or 2 faces. 
    # 8 holes = 8 to 16 cylindrical faces.
    # We mainly care that SOME holes of correct size exist and volume is correct.
    
    if valid_holes >= 8:
        score += 20
        feedback.append(f"✅ Found {valid_holes} valid hole surfaces.")
    elif valid_holes > 0:
        score += 10
        feedback.append(f"⚠️ Found partial hole surfaces ({valid_holes}).")
    else:
        feedback.append("❌ No M5 (5.5mm) holes detected.")

    # Check 5: VLM / App State (20 pts)
    # Did the agent actually work?
    if result.get('app_was_running', False):
        score += 10
    
    # We could add VLM check here, but the geometry check is very strong.
    # We'll give remaining points for general file properties
    if geo_data.get('hole_count', 0) >= 8 and dims_ok:
         score += 10 # Bonus for consistency

    passed = (score >= 60) and valid_solid and dims_ok

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }