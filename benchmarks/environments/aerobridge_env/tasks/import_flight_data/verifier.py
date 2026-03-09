#!/usr/bin/env python3
"""
Verifier for import_flight_data task.

Checks:
1. Flight plan "Draft Survey Mission" exists.
2. Start and End times match the requirements.
3. Geometry is a valid GeoJSON Polygon.
4. Coordinates match the requirements (checking for Lat/Lon swap).
5. Polygon loop is closed.
"""

import json
import os
import tempfile
import math

def verify_import_flight_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_start = metadata.get("expected_start_time", "2025-11-15 08:30:00")
    expected_end = metadata.get("expected_end_time", "2025-11-15 12:45:00")
    expected_coords = metadata.get("expected_coords", [])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check if record found (10 pts)
    if not result.get("found"):
        return {"passed": False, "score": 0, "feedback": "Flight Plan 'Draft Survey Mission' not found."}
    
    score += 10
    feedback.append("Flight Plan found.")

    # 2. Check Timestamps (30 pts)
    # Note: DB might return time with slight formatting diffs, but export script forces strftime format
    act_start = result.get("start_time", "")
    act_end = result.get("end_time", "")
    
    if act_start == expected_start:
        score += 15
        feedback.append("Start Time correct.")
    else:
        feedback.append(f"Start Time incorrect. Expected: {expected_start}, Got: {act_start}")

    if act_end == expected_end:
        score += 15
        feedback.append("End Time correct.")
    else:
        feedback.append(f"End Time incorrect. Expected: {expected_end}, Got: {act_end}")

    # 3. Check Geometry Structure (20 pts)
    geom = result.get("geometry")
    if not geom or not isinstance(geom, dict):
        feedback.append("Geometry is missing or invalid JSON.")
    else:
        g_type = geom.get("type")
        g_coords = geom.get("coordinates")
        
        if g_type == "Polygon" and isinstance(g_coords, list) and len(g_coords) > 0:
            score += 20
            feedback.append("Geometry is a valid GeoJSON Polygon.")
            
            # 4. Check Coordinates (30 pts)
            # GeoJSON Polygon coordinates are a list of rings (list of lists of [lon, lat])
            # The first ring is the outer boundary
            outer_ring = g_coords[0]
            
            # Check for closed loop (10 pts)
            if len(outer_ring) > 0 and outer_ring[0] == outer_ring[-1]:
                score += 10
                feedback.append("Polygon loop is closed.")
            else:
                feedback.append("Polygon loop is NOT closed.")

            # Check point accuracy (20 pts)
            # We compare point by point with tolerance
            matches = True
            if len(outer_ring) != len(expected_coords):
                matches = False
                feedback.append(f"Vertex count mismatch. Expected {len(expected_coords)}, got {len(outer_ring)}.")
            else:
                for i, (exp_pt, act_pt) in enumerate(zip(expected_coords, outer_ring)):
                    # exp_pt is [lon, lat]
                    # Check distance or simple diff
                    if not (math.isclose(exp_pt[0], act_pt[0], abs_tol=0.0005) and 
                            math.isclose(exp_pt[1], act_pt[1], abs_tol=0.0005)):
                        matches = False
                        feedback.append(f"Vertex {i} mismatch. Expected {exp_pt}, Got {act_pt}.")
                        
                        # Specific hint for Lat/Lon swap
                        if math.isclose(exp_pt[0], act_pt[1], abs_tol=0.0005) and math.isclose(exp_pt[1], act_pt[0], abs_tol=0.0005):
                            feedback.append("(It looks like Lat/Lon were swapped. GeoJSON uses [Lon, Lat]).")
                        break
            
            if matches:
                score += 20
                feedback.append("Coordinates match perfectly.")
        else:
            feedback.append(f"Geometry type mismatch or empty coordinates. Type: {g_type}")

    # Anti-gaming check (TS) - 10 pts
    if result.get("modified_after_start"):
        score += 10
        feedback.append("Modification timestamp valid.")
    else:
        # If timestamp check failed but data is correct, we might still allow it if model doesn't track TS
        # But here we assume we rely on it for full points
        feedback.append("Warning: Database record not flagged as modified during task window.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }