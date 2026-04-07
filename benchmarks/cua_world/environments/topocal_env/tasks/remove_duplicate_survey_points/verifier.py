#!/usr/bin/env python3
"""
Verifier for remove_duplicate_survey_points task.

Verification Strategy:
1. Copy results JSON and exported CSV file from the guest environment.
2. Ensure files were created *after* the task started (anti-gaming).
3. Check the number of rows in the CSV is precisely 387.
4. Mathematically compute pairwise horizontal distances of the exported coordinates.
5. Verify no two points remain closer than the expected threshold (0.045m to account for rounding).
6. Request VLM trajectory verification to ensure TopoCal UI was actively used.
"""

import json
import os
import math
import csv
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully used TopoCal CAD.

TASK: Remove duplicate survey points.

Review these trajectory frames from the agent's session and determine:
1. Did the agent open the TopoCal application?
2. Did the agent interact with menus for Point Utilities/Filters (e.g. look for words like 'Eliminar', 'Duplicados', 'Filtro', 'Puntos')?
3. Did the agent attempt to export a CSV or save the .tcl project?

Respond strictly in JSON format:
{
    "opened_topocal": true/false,
    "used_point_utilities": true/false,
    "saved_or_exported": true/false
}
"""

def verify_duplicate_removal(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_count', 387)
    
    score = 0
    feedback_parts = []
    
    # --- 1. Load result JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get("task_start", 0)
    
    # --- 2. Check Outputs Existence & Timestamps ---
    csv_exists = result.get("csv_exists", False)
    tcl_exists = result.get("tcl_exists", False)
    
    csv_modified_during_task = csv_exists and result.get("csv_mtime", 0) >= task_start
    tcl_modified_during_task = tcl_exists and result.get("tcl_mtime", 0) >= task_start

    if csv_modified_during_task:
        score += 20
        feedback_parts.append("✅ CSV exported during task (+20)")
    elif csv_exists:
        feedback_parts.append("❌ CSV exists but was not modified during task (anti-gaming check failed)")
    else:
        feedback_parts.append("❌ Missing expected CSV output")
        
    if tcl_modified_during_task:
        score += 10
        feedback_parts.append("✅ Project .tcl saved (+10)")

    # --- 3. Verify the CSV Data Integrity & Mathematics ---
    point_count = 0
    min_dist = float('inf')
    
    if csv_modified_during_task:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\cleaned_survey_points.csv", temp_csv.name)
            
            # Robustly parse coordinates without relying on Pandas (avoids missing dependency issues)
            xy_coords = []
            with open(temp_csv.name, 'r', encoding='utf-8-sig') as f:
                reader = csv.reader(f)
                for row in reader:
                    # Expecting format: Point, Easting, Northing, Elevation, Code
                    if len(row) >= 3:
                        try:
                            easting = float(row[1])
                            northing = float(row[2])
                            xy_coords.append((easting, northing))
                        except ValueError:
                            continue  # Skip header or malformed rows
                            
            point_count = len(xy_coords)
            
            # Check Point Count
            if point_count == expected_count:
                score += 20
                feedback_parts.append(f"✅ Exact expected point count: {point_count} (+20)")
            else:
                feedback_parts.append(f"❌ Incorrect point count: {point_count} (Expected: {expected_count})")
            
            # Compute Pairwise Minimum Distance
            for i in range(len(xy_coords)):
                for j in range(i + 1, len(xy_coords)):
                    dx = xy_coords[i][0] - xy_coords[j][0]
                    dy = xy_coords[i][1] - xy_coords[j][1]
                    dist = math.hypot(dx, dy)
                    if dist < min_dist:
                        min_dist = dist
            
            # 0.045m threshold used instead of 0.05m to account for potential float precision/rounding
            if min_dist >= 0.045 and point_count > 0:
                score += 30
                feedback_parts.append(f"✅ All duplicates successfully removed, minimum distance: {min_dist:.3f}m (+30)")
            elif point_count > 0:
                feedback_parts.append(f"❌ Duplicates still exist, minimum distance: {min_dist:.3f}m")

        except Exception as e:
            feedback_parts.append(f"❌ Error analyzing CSV data: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # --- 4. Trajectory VLM Verification ---
    vlm_query_fn = env_info.get('query_vlm')
    if vlm_query_fn:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_result = vlm_query_fn(prompt=VLM_PROMPT, images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("opened_topocal"):
                        score += 10
                        feedback_parts.append("✅ VLM confirmed TopoCal opened (+10)")
                    if parsed.get("used_point_utilities"):
                        score += 10
                        feedback_parts.append("✅ VLM confirmed usage of filtering UI (+10)")
        except Exception as e:
            logger.error(f"VLM Trajectory verification failed: {e}")

    # Pass logic: Needs to have successfully manipulated the points correctly
    passed = (score >= 70) and (point_count == expected_count) and (min_dist >= 0.045)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }