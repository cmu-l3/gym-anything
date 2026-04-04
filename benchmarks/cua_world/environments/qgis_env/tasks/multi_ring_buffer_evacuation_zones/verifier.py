#!/usr/bin/env python3
"""
Verifier for multi_ring_buffer_evacuation_zones task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_multi_ring_buffer(traj, env_info, task_info):
    """
    Verify that the agent created valid multi-ring buffers.

    Scoring (100 points total):
    - File exists and valid GeoJSON: 30 pts
    - File created during task: 10 pts
    - Correct feature count (9 features = 3 points * 3 rings): 20 pts
    - Geometry is Polygon/MultiPolygon: 15 pts
    - Distance/ring attributes present: 15 pts
    - File size non-trivial (>1KB): 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    
    # Criterion 1: File exists and is valid GeoJSON (30 pts)
    file_exists = result.get("file_exists", False)
    valid_geojson = result.get("is_valid_geojson", False)
    
    if file_exists and valid_geojson:
        score += 30
        feedback_parts.append("Valid GeoJSON output found")
    elif file_exists:
        score += 10
        feedback_parts.append("Output file exists but is not valid GeoJSON")
    else:
        feedback_parts.append("Output file NOT found")
        # Critical fail if no output
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # Criterion 2: File created during task (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp indicates pre-existing or unmodified file")

    # Criterion 3: Feature count (20 pts)
    # Expected: 3 points * 3 rings = 9 features
    feat_count = result.get("feature_count", 0)
    expected_count = 9
    
    if feat_count == expected_count:
        score += 20
        feedback_parts.append(f"Correct feature count ({feat_count})")
    elif feat_count >= 3:
        # Partial credit if they got some rings
        score += 10
        feedback_parts.append(f"Incorrect feature count ({feat_count}, expected {expected_count})")
    else:
        feedback_parts.append(f"Too few features ({feat_count})")

    # Criterion 4: Geometry type (15 pts)
    poly_count = result.get("polygon_feature_count", 0)
    if feat_count > 0 and poly_count == feat_count:
        score += 15
        feedback_parts.append("All features are Polygons")
    elif poly_count > 0:
        score += 5
        feedback_parts.append("Mixed geometry types found")
    else:
        feedback_parts.append("No polygon geometries found")

    # Criterion 5: Distance attributes (15 pts)
    if result.get("has_distance_attribute", False):
        score += 15
        attr_name = result.get("distance_attribute_name", "unknown")
        vals = result.get("unique_distance_values", [])
        feedback_parts.append(f"Distance attribute '{attr_name}' found with {len(vals)} unique values")
    else:
        feedback_parts.append("No distance/ring attributes found in output")

    # Criterion 6: Non-trivial size (10 pts)
    # Empty GeoJSON is small, populated one should be larger
    size = result.get("file_size_bytes", 0)
    if size > 1000:
        score += 10
        feedback_parts.append(f"File content size valid ({size} bytes)")
    elif size > 0:
        score += 5
        feedback_parts.append("File size small but non-empty")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }