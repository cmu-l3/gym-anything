#!/usr/bin/env python3
"""
Verifier for explode_multipart_geometries task.

Verifies:
1. Output shapefile exists
2. Output created during task session
3. Feature count increased (indicating explosion of multiparts)
4. Geometry type is Polygon (not MultiPolygon)
5. Attributes preserved
6. Specific multipart feature (Indonesia) was split
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_explode_multipart_geometries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_expected_features = metadata.get('min_expected_features', 200)
    original_features = metadata.get('original_features', 177)

    # Copy result from container
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
    feedback_parts = []
    
    # 1. Check file existence (10 pts)
    output_exists = result.get('output_exists', False)
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}

    # 2. Anti-gaming: Created during task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task session")

    # 3. Feature Count Analysis (30 pts)
    feature_count = int(result.get('feature_count', 0))
    if feature_count > min_expected_features:
        score += 30
        feedback_parts.append(f"Feature count increased correctly ({feature_count} > {original_features})")
    elif feature_count > original_features:
        score += 15
        feedback_parts.append(f"Feature count increased slightly ({feature_count}), but expected > {min_expected_features}")
    else:
        feedback_parts.append(f"Feature count did not increase ({feature_count} <= {original_features}) - Geometries not exploded?")

    # 4. Geometry Type (20 pts)
    geom_type = result.get('geometry_type', 'Unknown')
    # OGR usually reports "Polygon" for singlepart and "MultiPolygon" for multipart
    # However, sometimes it reports "Polygon" even if the file can technically hold multiparts but doesn't
    if "Polygon" in geom_type and "Multi" not in geom_type:
        score += 20
        feedback_parts.append("Geometry type is correctly Polygon")
    elif "Polygon" in geom_type:
        # If it says "MultiPolygon" but count increased, maybe partial credit? 
        # But specifically we want single parts.
        score += 5
        feedback_parts.append(f"Geometry type reported as {geom_type}")
    else:
        feedback_parts.append(f"Unexpected geometry type: {geom_type}")

    # 5. Attributes Preserved (10 pts)
    if result.get('attributes_preserved', False):
        score += 10
        feedback_parts.append("Attributes preserved")
    else:
        feedback_parts.append("Attributes missing in output")

    # 6. Specific Feature Check: Indonesia (20 pts)
    # Indonesia is a large archipelago. In singlepart, it should be many features.
    indonesia_count = int(result.get('indonesia_part_count', 0))
    if indonesia_count > 10:
        score += 20
        feedback_parts.append(f"Indonesia correctly split into {indonesia_count} parts")
    elif indonesia_count > 1:
        score += 10
        feedback_parts.append(f"Indonesia split into {indonesia_count} parts (expected > 10)")
    else:
        feedback_parts.append("Indonesia not split (count <= 1)")

    passed = score >= 60 and feature_count > original_features

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }