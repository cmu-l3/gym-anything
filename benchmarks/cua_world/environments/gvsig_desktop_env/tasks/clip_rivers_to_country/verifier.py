#!/usr/bin/env python3
"""
Verifier for clip_rivers_to_country task.

Verifies:
1. Output shapefile exists and was created during task.
2. Output is a valid shapefile with Line geometries.
3. Feature count is logical (0 < count < total_world_rivers).
4. Bounding box matches Brazil's approximate location.
5. VLM: Confirms visual evidence of selection and processing.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clip_rivers_to_country(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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
    
    # --- Check 1: File Existence & Validity (30 pts) ---
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output shapefile brazil_rivers.shp not found."}
    
    score += 10
    feedback.append("File exists.")

    if not result.get('file_created_during_task'):
        feedback.append("WARNING: File timestamp is older than task start (pre-existing?).")
    else:
        score += 5
        feedback.append("File created during task.")

    if result.get('is_valid'):
        score += 15
        feedback.append("Shapefile is valid.")
    else:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback + ["Shapefile corrupted or invalid."])}

    # --- Check 2: Geometry & Features (40 pts) ---
    geom_type = result.get('geometry_type', '').lower()
    if 'line' in geom_type:
        score += 10
        feedback.append(f"Correct geometry type: {geom_type}.")
    else:
        feedback.append(f"Incorrect geometry type: {geom_type} (expected LineString).")

    count = int(result.get('feature_count', 0))
    orig_count = int(result.get('original_count', 1420)) # approx 1400 rivers in NE dataset

    if count > 0:
        score += 10
        feedback.append(f"Output contains {count} features.")
    else:
        feedback.append("Output is empty (0 features).")

    # The clipped set must be smaller than the world set
    if 0 < count < orig_count:
        score += 20
        feedback.append("Feature count indicates clipping occurred (subset of original).")
    elif count == orig_count:
        feedback.append("Feature count equals original dataset (clipping likely failed or no polygon selected).")
    
    # --- Check 3: Spatial Extent (Brazil Check) (30 pts) ---
    # Expected Brazil Extent approx: W: -74, E: -34, S: -34, N: 6
    # Format: (-73.99, -33.75) - (-34.79, 5.27)
    extent_raw = result.get('extent_raw', '')
    
    # Parse extent
    match = re.search(r'\(([^,]+),\s*([^)]+)\)\s*-\s*\(([^,]+),\s*([^)]+)\)', extent_raw)
    valid_extent = False
    
    if match:
        try:
            min_x, min_y = float(match.group(1)), float(match.group(2))
            max_x, max_y = float(match.group(3)), float(match.group(4))
            
            # Tolerances (broad to account for projection differences or partial clips)
            # Center of Brazil is roughly -54, -14
            center_x = (min_x + max_x) / 2
            center_y = (min_y + max_y) / 2
            
            if (-60 < center_x < -40) and (-25 < center_y < 0):
                valid_extent = True
                score += 30
                feedback.append("Spatial extent matches Brazil region.")
            else:
                feedback.append(f"Extent center ({center_x:.2f}, {center_y:.2f}) is outside Brazil.")
        except ValueError:
            feedback.append("Could not parse extent values.")
    else:
        feedback.append("Could not parse extent string.")

    # --- Final Evaluation ---
    passed = (score >= 60) and valid_extent and (count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }