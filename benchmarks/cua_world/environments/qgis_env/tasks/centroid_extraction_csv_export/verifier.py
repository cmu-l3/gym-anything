#!/usr/bin/env python3
"""Verifier for centroid_extraction_csv_export task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_centroid_extraction(traj, env_info, task_info):
    """
    Verify that South American country centroids were extracted and exported to CSV.

    Scoring (100 points):
    - File exists: 10 pts
    - Valid CSV structure: 10 pts
    - Correct row count (10-15): 20 pts
    - Longitude range valid (-85 to -30): 15 pts
    - Latitude range valid (-60 to 15): 15 pts
    - Known countries present: 20 pts
    - File freshness (created during task): 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_countries = metadata.get('required_countries', ["Brazil", "Argentina", "Chile", "Colombia", "Peru"])
    
    # Load result
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

    # 1. File Exists (10 pts)
    if result.get('file_exists', False):
        score += 10
        subscores["file_exists"] = True
        feedback_parts.append("CSV file found")
    else:
        feedback_parts.append("CSV file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid CSV (10 pts)
    if analysis.get('valid_csv', False):
        score += 10
        subscores["valid_csv"] = True
        feedback_parts.append("Valid CSV format")
    else:
        feedback_parts.append("Invalid or unreadable CSV")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Row Count (20 pts)
    # Natural Earth South America typically has 13-14 countries
    row_count = analysis.get('row_count', 0)
    if 10 <= row_count <= 20:
        score += 20
        subscores["row_count"] = True
        feedback_parts.append(f"Row count correct ({row_count})")
    else:
        subscores["row_count"] = False
        feedback_parts.append(f"Row count incorrect: {row_count} (expected 10-20)")

    # 4. Longitude Range (15 pts)
    # SA approx: -82 to -34
    lon_range = analysis.get('lon_range', [0, 0])
    if analysis.get('coords_valid') and -85 <= lon_range[0] and lon_range[1] <= -30:
        score += 15
        subscores["lon_valid"] = True
        feedback_parts.append("Longitude values within SA range")
    else:
        subscores["lon_valid"] = False
        feedback_parts.append(f"Longitude values out of range or missing: {lon_range}")

    # 5. Latitude Range (15 pts)
    # SA approx: -55 to +12
    lat_range = analysis.get('lat_range', [0, 0])
    if analysis.get('coords_valid') and -60 <= lat_range[0] and lat_range[1] <= 15:
        score += 15
        subscores["lat_valid"] = True
        feedback_parts.append("Latitude values within SA range")
    else:
        subscores["lat_valid"] = False
        feedback_parts.append(f"Latitude values out of range or missing: {lat_range}")

    # 6. Known Countries (20 pts)
    found_countries = [c.lower() for c in analysis.get('countries_found', [])]
    matched_count = 0
    for req in expected_countries:
        if any(req.lower() in c for c in found_countries):
            matched_count += 1
            
    if matched_count >= 3:
        score += 20
        subscores["countries_found"] = True
        feedback_parts.append(f"Found {matched_count} key countries")
    elif matched_count > 0:
        score += 10
        subscores["countries_found"] = False
        feedback_parts.append(f"Found only {matched_count} key countries")
    else:
        subscores["countries_found"] = False
        feedback_parts.append("No specific South American countries identified")

    # 7. File Freshness (10 pts)
    if result.get('file_fresh', False):
        score += 10
        subscores["fresh"] = True
        feedback_parts.append("File created during task")
    else:
        subscores["fresh"] = False
        feedback_parts.append("File timestamp indicates it was pre-existing or not updated")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }