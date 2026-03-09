#!/usr/bin/env python3
"""Verifier for pole_of_inaccessibility_somalia task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_pole_of_inaccessibility(traj, env_info, task_info):
    """
    Verify the calculation of the Pole of Inaccessibility for Somalia.
    
    Scoring (100 points):
    - GeoJSON exists: 10 pts
    - Valid GeoJSON (Point feature): 10 pts
    - Feature count is exactly 1: 10 pts
    - Point is within expected Somalia bounding box: 30 pts
    - Report file exists: 10 pts
    - Report value is within valid range (200-600 km): 20 pts
    - GeoJSON contains distance attribute: 10 pts
    
    Pass threshold: 65 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    metadata = task_info.get('metadata', {})
    
    # Read result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
        
    score = 0
    feedback_parts = []
    
    geojson_analysis = result.get('geojson_analysis', {})
    
    # 1. GeoJSON Exists (10)
    if result.get('geojson_exists', False):
        score += 10
        feedback_parts.append("GeoJSON file created")
    else:
        feedback_parts.append("GeoJSON file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Valid GeoJSON & Feature Count (20)
    if geojson_analysis.get('valid', False) and geojson_analysis.get('feature_count') == 1:
        score += 10
        if geojson_analysis.get('geometry_type') == "Point":
            score += 10
            feedback_parts.append("Valid Point feature")
        else:
            feedback_parts.append(f"Invalid geometry: {geojson_analysis.get('geometry_type')}")
    else:
        feedback_parts.append("Invalid GeoJSON or wrong feature count")
        
    # 3. Location Check (30)
    # Somalia rough bbox: Long 40-52, Lat -2-12
    coords = geojson_analysis.get('coordinates', [])
    if coords and len(coords) >= 2:
        lon, lat = coords[0], coords[1]
        # Reprojection might mean coords are in meters (Web Mercator)
        # If huge numbers, they are meters. If small, degrees.
        # The task asked to reproject, so output MIGHT be in meters if they saved the reprojected layer
        # OR degrees if they exported to WGS84.
        # Let's handle both.
        
        in_bbox = False
        # Degrees check
        if 40.0 <= lon <= 55.0 and -2.0 <= lat <= 13.0:
            in_bbox = True
            feedback_parts.append(f"Location valid (WGS84): {lon:.2f}, {lat:.2f}")
        # Meters check (Web Mercator approx bounds for Somalia)
        # x: ~4,450,000 to ~5,700,000
        # y: ~-220,000 to ~1,300,000
        elif 4000000 <= lon <= 6000000 and -300000 <= lat <= 1500000:
            in_bbox = True
            feedback_parts.append("Location valid (Metric)")
            
        if in_bbox:
            score += 30
        else:
            feedback_parts.append(f"Point location out of bounds: {lon}, {lat}")
    else:
        feedback_parts.append("No coordinates found")

    # 4. Attribute Check (10)
    dist_attr = geojson_analysis.get('distance_attribute')
    if dist_attr is not None:
        score += 10
        feedback_parts.append("Distance attribute found in GeoJSON")
    else:
        feedback_parts.append("Distance attribute missing from GeoJSON")
        
    # 5. Report Check (10 + 20)
    if result.get('report_exists', False):
        score += 10
        try:
            val = float(result.get('report_value', 0))
            # Expected range: 200km - 600km
            # If they reported meters (e.g. 350000), handle that too
            if val > 10000: 
                val = val / 1000.0 # Convert assumed meters to km
            
            if 200 <= val <= 600:
                score += 20
                feedback_parts.append(f"Reported distance valid: {val:.1f} km")
            else:
                feedback_parts.append(f"Reported distance out of range: {val}")
        except ValueError:
            feedback_parts.append("Could not parse report value")
    else:
        feedback_parts.append("Report file missing")

    # Check anti-gaming
    if not result.get('files_created_during_task', False):
        feedback_parts.append("WARNING: Files not created during task window")
        score = min(score, 50) # Penalty

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }