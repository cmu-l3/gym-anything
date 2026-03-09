#!/usr/bin/env python3
"""
Verifier for extract_kenya_utm_projection task.

Checks:
1. Output shapefile exists and was created during the task.
2. Contains exactly one feature (Kenya).
3. Coordinate Reference System is UTM Zone 37S (EPSG:32737).
4. Coordinates are metric (projected), not geographic (degrees).
"""

import json
import os
import sys
import tempfile
import logging
import struct

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_kenya_utm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Load result metadata from container
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

    # Basic checks
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output shapefile 'kenya_utm.shp' not found."}

    score = 20
    feedback_parts = ["File created"]

    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("File timestamp too old")

    # 2. Check CRS from PRJ content (available in JSON)
    prj_content = result.get("prj_content", "")
    crs_correct = False
    
    # Check for key identifiers in WKT
    # UTM Zone 37S identifiers: "32737", "UTM zone 37S", "UTM_Zone_37S"
    if "32737" in prj_content or ("UTM" in prj_content and "37S" in prj_content):
        score += 30
        crs_correct = True
        feedback_parts.append("CRS is UTM Zone 37S")
    else:
        feedback_parts.append(f"Incorrect CRS: {prj_content[:50]}...")

    # 3. Analyze Shapefile Content (Feature Count and Coordinates)
    # We need to copy the SHP and SHX out to analyze them
    temp_dir = tempfile.mkdtemp()
    shp_path = os.path.join(temp_dir, "kenya.shp")
    shx_path = os.path.join(temp_dir, "kenya.shx")
    
    try:
        copy_from_env(result["output_shp_path"], shp_path)
        copy_from_env(result["output_shx_path"], shx_path)
        
        # Simple binary parsing to avoid dependency hell if pyshp not available
        # But we'll try to use pyshp if available, otherwise fallback to struct
        
        try:
            import shapefile
            sf = shapefile.Reader(shp_path)
            num_features = len(sf)
            bbox = sf.bbox
            
            # Check 1: Feature Count
            if num_features == 1:
                score += 20
                feedback_parts.append("Contains 1 feature (Correct)")
            else:
                feedback_parts.append(f"Contains {num_features} features (Expected 1)")

            # Check 2: Coordinate system units (Metric vs Degrees)
            # Kenya in degrees: Lon ~34-42, Lat ~-5-5
            # Kenya in UTM 37S: Easting ~200k-800k, Northing ~9.5M-10M (or near 0/equator)
            # If any coordinate is > 1000, it's projected (Metric)
            
            is_metric = bbox[0] > 180 or bbox[1] > 90 or bbox[2] > 180 or bbox[3] > 90
            
            if is_metric:
                score += 20
                feedback_parts.append("Coordinates are projected/metric")
            else:
                feedback_parts.append("Coordinates look like Lat/Lon (Degrees) - Reprojection Failed")

        except ImportError:
            # Fallback: Read SHX file header for file length to estimate features
            # SHX header is 100 bytes. Records are 8 bytes (offset + length).
            file_size = os.path.getsize(shx_path)
            num_features = (file_size - 100) // 8
            
            if num_features == 1:
                score += 20
                feedback_parts.append("Contains 1 feature (Correct)")
            else:
                feedback_parts.append(f"Contains {num_features} features (Expected 1)")
                
            # Fallback: Read SHP file bounding box from header
            # Bytes 36-68 contain Bounding Box (4 doubles: minX, minY, maxX, maxY)
            with open(shp_path, "rb") as f:
                f.seek(36)
                bbox_bytes = f.read(32)
                minx, miny, maxx, maxy = struct.unpack("<dddd", bbox_bytes)
                
            is_metric = minx > 180 or miny > 90 or maxx > 180 or maxy > 90
            if is_metric:
                score += 20
                feedback_parts.append("Coordinates are projected/metric")
            else:
                feedback_parts.append("Coordinates look like Lat/Lon")

    except Exception as e:
        feedback_parts.append(f"Failed to analyze shapefile geometry: {e}")
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 80 and crs_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }