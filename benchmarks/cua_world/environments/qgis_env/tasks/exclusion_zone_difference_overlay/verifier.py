#!/usr/bin/env python3
"""Verifier for exclusion_zone_difference_overlay task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_exclusion_zone_difference_overlay(traj, env_info, task_info):
    """
    Verify that the agent performed the difference overlay correctly to remove exclusion zones.

    Scoring (100 points):
    - File Artifact (10): Output file exists and is valid.
    - Geometry Type (10): Output contains Polygons.
    - Operation Executed (30): Area significantly reduced (indicates subtraction).
    - Constraint Respected (30): Output does not intersect with 1km buffers around inputs.
    - Attributes Retained (10): Original names present.
    - Metric Accuracy (10): Removed area is plausible (indicates correct UTM projection).

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

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
    
    # 1. File Artifact (10 pts)
    if result.get('file_exists', False) and analysis.get('valid_geojson', False):
        score += 10
        subscores['file_valid'] = True
        feedback_parts.append("Valid GeoJSON output found")
    else:
        subscores['file_valid'] = False
        feedback_parts.append("Output file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Geometry Type (10 pts)
    if analysis.get('has_polygons', False):
        score += 10
        subscores['geometry_type'] = True
        feedback_parts.append("Geometry type is Polygon")
    else:
        feedback_parts.append("Incorrect geometry type (expected Polygons)")

    # 3. Operation Executed / Area Reduction (30 pts)
    input_area = analysis.get('input_area_sqkm', 0)
    output_area = analysis.get('output_area_sqkm', 0)
    area_removed = analysis.get('area_removed_sqkm', 0)
    
    # Expecting noticeable reduction. 
    # Input is ~18.7 sq km total. 
    # 3 buffers * 3.14 sq km = ~9.4 sq km max potential reduction (if fully inside).
    # Realistically, buffers might overlap boundaries, but reduction should be > 0.1 sq km.
    if input_area > 0 and output_area < input_area and area_removed > 0.1:
        score += 30
        subscores['area_reduced'] = True
        feedback_parts.append(f"Area reduced by {area_removed:.2f} sq km")
    else:
        feedback_parts.append(f"Area did not decrease significantly (In: {input_area:.2f}, Out: {output_area:.2f})")

    # 4. Constraint Respected (30 pts)
    if analysis.get('constraint_respected', False):
        score += 30
        subscores['constraint_respected'] = True
        feedback_parts.append("No overlap with exclusion zones (buffers respected)")
    else:
        feedback_parts.append("Output polygons intersect with exclusion zones (Difference failed)")

    # 5. Attributes Retained (10 pts)
    if analysis.get('attributes_retained', False):
        score += 10
        subscores['attributes'] = True
        feedback_parts.append("Attributes retained")
    else:
        feedback_parts.append("Attributes lost")

    # 6. Metric Accuracy (10 pts)
    # If they didn't reproject and buffered by "1000" degrees, the result would be empty (everything removed) or massive errors.
    # If they buffered by 1000 degrees, the buffer is huge.
    # If they buffered by 0.01 degrees (~1km), it might be close but imprecise.
    # The 'area_removed' logic above covers 'something was removed', but here we check plausibility.
    # Expected removal is between 1 and 10 sq km.
    if 1.0 < area_removed < 12.0:
        score += 10
        subscores['metric_accuracy'] = True
        feedback_parts.append("Removed area is plausible for 1km buffers")
    else:
        feedback_parts.append("Removed area seems implausible (check CRS units)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }