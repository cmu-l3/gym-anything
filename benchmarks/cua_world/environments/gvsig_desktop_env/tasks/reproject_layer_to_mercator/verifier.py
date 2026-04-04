#!/usr/bin/env python3
"""
Verifier for reproject_layer_to_mercator task.

Verifies that:
1. The output shapefile exists and was created during the task.
2. The .prj file indicates a Mercator projection (EPSG:3857).
3. The shapefile coordinates are actually projected (in meters, not degrees).
4. The feature count matches the input dataset.
"""

import json
import os
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reproject_layer_to_mercator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_feature_count', 177)
    min_x_range = metadata.get('min_x_range_meters', 1000000.0)
    target_keywords = metadata.get('target_crs_keywords', ["Mercator", "3857", "Pseudo_Mercator"])

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence & Timestamp (30 points)
    files_exist = (result.get('shp_exists') and result.get('shx_exists') and 
                   result.get('dbf_exists') and result.get('prj_exists'))
    created_fresh = result.get('file_created_during_task', False)

    if files_exist:
        score += 15
        feedback_parts.append("Shapefile components found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile missing components."}

    if created_fresh:
        score += 15
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this task.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 2. Analyze PRJ Content (25 points)
    # Check if projection text contains Mercator keywords
    temp_prj = tempfile.NamedTemporaryFile(delete=False, suffix='.prj')
    prj_valid = False
    try:
        copy_from_env("/tmp/result_output.prj", temp_prj.name)
        with open(temp_prj.name, 'r') as f:
            prj_content = f.read()
            
        # Check for keywords
        if any(kw.lower() in prj_content.lower() for kw in target_keywords):
            prj_valid = True
            score += 25
            feedback_parts.append("PRJ file indicates Mercator projection.")
        else:
            feedback_parts.append(f"PRJ file does not appear to be Web Mercator. Content snippet: {prj_content[:100]}...")
            
        # Check against pure GCS (Geographic)
        if "GEOGCS" in prj_content and "PROJCS" not in prj_content:
            feedback_parts.append("PRJ is still Geographic (Lat/Lon), not Projected.")
            prj_valid = False
            
    except Exception as e:
        feedback_parts.append(f"Error reading PRJ: {str(e)}")
    finally:
        if os.path.exists(temp_prj.name):
            os.unlink(temp_prj.name)

    # 3. Analyze Coordinates via SHP Header (30 points)
    # We parse the binary header to check the Bounding Box
    # Bytes 36-67: MinX, MinY, MaxX, MaxY (Little Endian Doubles)
    temp_shp = tempfile.NamedTemporaryFile(delete=False, suffix='.shp')
    coords_valid = False
    try:
        copy_from_env("/tmp/result_output.shp", temp_shp.name)
        with open(temp_shp.name, 'rb') as f:
            header = f.read(100)
            if len(header) >= 68:
                # Unpack bounding box (Little Endian <, 4 doubles d)
                bbox = struct.unpack('<4d', header[36:68])
                min_x, min_y, max_x, max_y = bbox
                
                x_range = abs(max_x - min_x)
                y_range = abs(max_y - min_y)
                
                feedback_parts.append(f"Bounding Box X-Range: {x_range:.2f}")
                
                # Web Mercator world width is ~40,075,000 meters
                # Geographic is 360 degrees
                # We use a threshold of 1,000,000 to be safe
                if x_range > min_x_range:
                    coords_valid = True
                    score += 30
                    feedback_parts.append("Coordinates confirm data is projected in meters.")
                else:
                    feedback_parts.append(f"Coordinates appear to be in degrees (Range < {min_x_range}). Data not reprojected.")
            else:
                feedback_parts.append("Invalid SHP header size.")
    except Exception as e:
        feedback_parts.append(f"Error reading SHP header: {str(e)}")
    finally:
        if os.path.exists(temp_shp.name):
            os.unlink(temp_shp.name)

    # 4. Analyze Feature Count via SHX (15 points)
    # SHX file: 100 byte header + 8 bytes per record (Offset + ContentLength)
    # File Size = 100 + (NumRecords * 8)
    # NumRecords = (FileSize - 100) / 8
    temp_shx = tempfile.NamedTemporaryFile(delete=False, suffix='.shx')
    try:
        copy_from_env("/tmp/result_output.shx", temp_shx.name)
        file_size = os.path.getsize(temp_shx.name)
        if file_size >= 100:
            count = (file_size - 100) // 8
            # Allow slight tolerance (e.g., if polar regions were clipped)
            if abs(count - expected_count) <= 5:
                score += 15
                feedback_parts.append(f"Feature count correct ({count}).")
            else:
                feedback_parts.append(f"Feature count mismatch: got {count}, expected ~{expected_count}.")
    except Exception as e:
        feedback_parts.append(f"Error checking feature count: {str(e)}")
    finally:
        if os.path.exists(temp_shx.name):
            os.unlink(temp_shx.name)

    # Final Pass Determination
    # Must have files, created fresh, correct PRJ, AND correct Coordinates
    passed = (files_exist and created_fresh and prj_valid and coords_valid)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }