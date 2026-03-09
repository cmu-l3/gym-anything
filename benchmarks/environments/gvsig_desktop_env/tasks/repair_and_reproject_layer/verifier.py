#!/usr/bin/env python3
"""
Verifier for repair_and_reproject_layer task.

Criteria:
1. Output shapefile exists and was created during the task.
2. Output .prj file exists and defines Web Mercator (EPSG:3857).
3. Output .shp file coordinate data is actually transformed (values in meters, not degrees).
"""

import json
import os
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repair_and_reproject_layer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: File Existence & Timestamp (20 points)
    if not result.get('shp_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output shapefile not found at expected path."
        }
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("File exists but was NOT created during this task session.")
        # We allow continuation but with heavy penalty if we suspected cheating, 
        # but here we just fail essentially as it implies pre-existing data or gaming.
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file timestamp predates task start."
        }
    
    score += 20
    feedback_parts.append("Output shapefile created.")

    # Check 2: PRJ Content (30 points)
    # We need to copy the .prj file out to verify its content
    prj_path = result.get('output_prj_path')
    if result.get('prj_exists', False) and prj_path:
        temp_prj = tempfile.NamedTemporaryFile(delete=False, suffix='.prj')
        try:
            copy_from_env(prj_path, temp_prj.name)
            with open(temp_prj.name, 'r') as f:
                wkt_content = f.read().lower()
            
            # Look for Mercator keywords
            if any(k in wkt_content for k in ["mercator", "3857", "pseudo_mercator"]):
                score += 30
                feedback_parts.append("Projection definition confirms Web Mercator.")
            else:
                feedback_parts.append("Projection file exists but does not appear to be Mercator.")
        except Exception as e:
            feedback_parts.append(f"Failed to verify PRJ content: {e}")
        finally:
            if os.path.exists(temp_prj.name):
                os.unlink(temp_prj.name)
    else:
        feedback_parts.append("Missing .prj file (projection undefined).")

    # Check 3: Coordinate Transformation (50 points)
    # This is the most critical check. Did the agent actually reproject the data?
    # We parse the SHP header to check the Bounding Box.
    shp_path = result.get('output_shp_path')
    temp_shp = tempfile.NamedTemporaryFile(delete=False, suffix='.shp')
    
    try:
        copy_from_env(shp_path, temp_shp.name)
        
        # Shapefile Header Format (Little Endian):
        # Bytes 0-24: File Code, Unused
        # Bytes 24-28: File Length
        # Bytes 28-32: Version
        # Bytes 32-36: Shape Type
        # Bytes 36-68: Bounding Box (MinX, MinY, MaxX, MaxY) - 4 doubles (8 bytes each)
        
        with open(temp_shp.name, 'rb') as f:
            f.seek(36)
            bbox_data = f.read(32)
            
        if len(bbox_data) == 32:
            minx, miny, maxx, maxy = struct.unpack('<dddd', bbox_data)
            
            # WGS84 (Degrees) range: X[-180, 180], Y[-90, 90]
            # Web Mercator (Meters) range: X[~-20mil, ~20mil], Y[~-20mil, ~20mil]
            
            # We check if values are "large" (indicating meters)
            is_meters = (abs(maxx) > 200000 or abs(minx) > 200000)
            
            if is_meters:
                score += 50
                feedback_parts.append("Coordinates are in meters (Transformation verified).")
            else:
                feedback_parts.append(f"Coordinates appear to be in degrees (X range: {minx:.2f} to {maxx:.2f}). Reprojection failed.")
        else:
            feedback_parts.append("Invalid shapefile header.")
            
    except Exception as e:
        feedback_parts.append(f"Failed to analyze shapefile geometry: {e}")
    finally:
        if os.path.exists(temp_shp.name):
            os.unlink(temp_shp.name)

    passed = (score >= 90)  # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }