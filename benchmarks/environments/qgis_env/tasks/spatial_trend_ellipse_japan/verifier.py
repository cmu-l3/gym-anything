#!/usr/bin/env python3
"""Verifier for spatial_trend_ellipse_japan task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_spatial_trend_ellipse_japan(traj, env_info, task_info):
    """
    Verify the calculation of the Standard Deviational Ellipse for Japan.

    Scoring (100 points):
    - File created/exists (20 pts)
    - Valid GeoJSON (20 pts)
    - Exactly 1 feature (15 pts) - Ellipse is a single polygon
    - Geometry is Polygon (15 pts)
    - Centroid location in Japan (15 pts) - Rough bounds check
    - Statistical attributes present (15 pts) - Evidence of algorithm usage

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Get bounds from metadata
    metadata = task_info.get('metadata', {})
    bounds = metadata.get('bounds', {
        "min_lon": 128.0,
        "max_lon": 147.0,
        "min_lat": 30.0,
        "max_lat": 46.0
    })

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

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}
    
    analysis = result.get('analysis', {})

    # 1. File Existence & Freshness (20 pts)
    if result.get('file_exists', False) and result.get('file_new', False):
        score += 20
        subscores['file'] = True
        feedback_parts.append("New output file found")
    elif result.get('file_exists', False):
        score += 10
        subscores['file'] = True
        feedback_parts.append("Output file found (but timestamp ambiguous)")
    else:
        subscores['file'] = False
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid GeoJSON (20 pts)
    if analysis.get('valid_geojson', False):
        score += 20
        subscores['valid_json'] = True
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores['valid_json'] = False
        feedback_parts.append("Invalid or empty GeoJSON")

    # 3. Feature Count (15 pts)
    count = analysis.get('feature_count', 0)
    if count == 1:
        score += 15
        subscores['count'] = True
        feedback_parts.append("Correct feature count (1)")
    else:
        subscores['count'] = False
        feedback_parts.append(f"Incorrect feature count: {count} (expected 1)")

    # 4. Geometry Type (15 pts)
    geom_type = analysis.get('geometry_type', 'Unknown')
    if geom_type in ['Polygon', 'MultiPolygon']:
        score += 15
        subscores['geometry'] = True
        feedback_parts.append("Correct geometry type (Polygon)")
    else:
        subscores['geometry'] = False
        feedback_parts.append(f"Incorrect geometry type: {geom_type}")

    # 5. Spatial Location (15 pts)
    lon = analysis.get('centroid_lon', 0)
    lat = analysis.get('centroid_lat', 0)
    
    in_lon = bounds['min_lon'] <= lon <= bounds['max_lon']
    in_lat = bounds['min_lat'] <= lat <= bounds['max_lat']
    
    if in_lon and in_lat:
        score += 15
        subscores['location'] = True
        feedback_parts.append(f"Location correct (Lat: {lat:.2f}, Lon: {lon:.2f})")
    else:
        subscores['location'] = False
        feedback_parts.append(f"Location out of bounds (Lat: {lat:.2f}, Lon: {lon:.2f}) - Expected Japan")

    # 6. Attributes (15 pts)
    if analysis.get('has_stat_attributes', False):
        score += 15
        subscores['attributes'] = True
        feedback_parts.append("Statistical attributes found")
    else:
        subscores['attributes'] = False
        feedback_parts.append("Missing statistical attributes (algorithm output fields)")

    passed = score >= 60 and subscores.get('file', False) and subscores.get('geometry', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }