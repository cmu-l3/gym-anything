#!/usr/bin/env python3
"""
Verifier for river_floodplain_transects task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_river_floodplain_transects(traj, env_info, task_info):
    """
    Verify the generation of river transects.
    
    Criteria:
    1. Output file exists and is valid GeoJSON (20 pts)
    2. Feature count is within expected range (120-170) (25 pts)
       - Danube is ~2850km. 20km spacing = ~142 transects.
    3. Features are LineStrings (10 pts)
    4. Length check (Metres vs Degrees check) (25 pts)
       - If projected correctly, length ~ 10,000 units (meters)
       - Or if reprojected back to WGS84 for export, geodetic length ~ 10km.
    5. Location/Bbox check (20 pts)
       - Must be in Europe/Danube region.
    """
    
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
    
    # 1. File Existence & Validity
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("is_new"):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during this task (stale data)."}

    analysis = result.get("analysis", {})
    if not analysis.get("valid"):
        return {"passed": False, "score": 0, "feedback": "Output file is not valid GeoJSON."}
    
    score += 20
    feedback.append("Valid GeoJSON created.")

    # 2. Feature Count
    count = analysis.get("count", 0)
    min_c = task_info.get("metadata", {}).get("min_feature_count", 120)
    max_c = task_info.get("metadata", {}).get("max_feature_count", 170)
    
    if min_c <= count <= max_c:
        score += 25
        feedback.append(f"Feature count {count} is within expected range ({min_c}-{max_c}).")
    else:
        # Partial credit if somewhat close (e.g. they didn't dissolve perfectly so have duplicates, or different spacing)
        if count > 50 and count < 300:
            score += 10
            feedback.append(f"Feature count {count} is outside optimal range ({min_c}-{max_c}) but plausible.")
        else:
            feedback.append(f"Feature count {count} is incorrect (expected {min_c}-{max_c}). Did you filter for 'Danube' and use 20km spacing?")

    # 3. Geometry Type
    geom_types = analysis.get("geom_types", [])
    if "LineString" in geom_types and len(geom_types) == 1:
        score += 10
        feedback.append("Geometry type is correct (LineString).")
    else:
        feedback.append(f"Geometry type mismatch: found {geom_types}, expected ['LineString'].")

    # 4. Length / Projection Check
    # This checks if they correctly worked in meters.
    avg_len = analysis.get("avg_length", 0)
    is_metric_coords = analysis.get("is_metric_coords", False)
    
    target_len = 10000 # meters
    tolerance = 1000   # +/- 1km
    
    length_passed = False
    
    if is_metric_coords:
        # Coords are projected (e.g. 3857). Units are meters.
        if abs(avg_len - target_len) < tolerance:
            score += 25
            length_passed = True
            feedback.append(f"Transect lengths are correct (~{int(avg_len)}m). Metric CRS confirmed.")
        else:
            feedback.append(f"Transect lengths ({int(avg_len)}) don't match expected 10km. Metric CRS used but length wrong.")
    else:
        # Coords are Geographic (Degrees).
        # Two possibilities:
        # A) They generated in degrees. If they input '10000', result is 10000 degrees (huge).
        # B) They generated in meters (reprojected) then exported to WGS84.
        #    In this case, Euclidean length of WGS84 coords will be small (deg), but Haversine would be ~10km.
        #    However, the export script calculated 'avg_len' as Euclidean.
        
        # 10km in degrees is roughly 0.09 to 0.14 depending on latitude.
        if 0.05 < avg_len < 0.2:
            score += 25
            length_passed = True
            feedback.append("Transect lengths appear correct in WGS84 (~10km converted to degrees).")
        elif avg_len > 100:
            feedback.append(f"Transect lengths are huge ({avg_len} deg). You likely generated transects using '10000' length on a WGS84 layer (Degrees) instead of reprojecting to Meters first.")
        else:
            feedback.append(f"Transect lengths ({avg_len}) are incorrect.")

    # 5. Location Check
    bbox = analysis.get("bbox", [0,0,0,0]) # minx, miny, maxx, maxy
    # Danube approx: Lon 8 to 30, Lat 43 to 49
    # If metric, this check is harder without complex reprojection in verifier.
    # But if length check passed, we trust the geometry somewhat.
    # Let's rely on metric coords flag or rough WGS84 bounds.
    
    if is_metric_coords:
        # Just check validity if we already confirmed length and count
        if length_passed:
            score += 20
            feedback.append("Spatial location accepted (Metric CRS).")
        else:
            # If length failed, we can't be sure where this is, but give points if bbox is not 0,0,0,0
            if bbox != [0,0,0,0] and bbox != [float('inf'), float('inf'), float('-inf'), float('-inf')]:
                score += 10
                feedback.append("Spatial data present but validation limited due to length mismatch.")
    else:
        # WGS84 check
        # Check intersection with Europe box: Lon -10 to 40, Lat 35 to 70
        if (bbox[0] > -10 and bbox[2] < 50 and bbox[1] > 35 and bbox[3] < 70):
            score += 20
            feedback.append("Transects are located correctly in Europe.")
        else:
            feedback.append(f"Transects appear to be in wrong location: {bbox}.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }