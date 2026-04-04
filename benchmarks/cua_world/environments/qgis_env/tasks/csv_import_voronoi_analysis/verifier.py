#!/usr/bin/env python3
"""
Verifier for CSV Import and Voronoi Analysis task.

Task requirements:
1. CSV imported (implied by next steps)
2. Voronoi polygons generated
3. Exported to GeoJSON
4. Attributes preserved
5. Correct geometry type (Polygon)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_csv_import_voronoi_analysis(traj, env_info, task_info):
    """
    Verify the Voronoi analysis task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Verification data: {json.dumps(result, indent=2)}")

    score = 0
    max_score = 100
    feedback_parts = []
    subscores = {}

    # Criterion 1: Output file exists (15 points)
    if result.get("file_exists", False):
        score += 15
        subscores["file_exists"] = True
        feedback_parts.append("Output file found")
    else:
        subscores["file_exists"] = False
        feedback_parts.append("Output file NOT found")
        # Early exit if file missing
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Criterion 2: Valid GeoJSON format (15 points)
    if result.get("valid_geojson", False):
        score += 15
        subscores["valid_geojson"] = True
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores["valid_geojson"] = False
        feedback_parts.append("Invalid GeoJSON content")

    # Criterion 3: Polygon geometry (20 points)
    geom_types = result.get("geometry_types", [])
    has_polygons = any(gt in ["Polygon", "MultiPolygon"] for gt in geom_types)
    if has_polygons:
        score += 20
        subscores["geometry"] = True
        feedback_parts.append(f"Correct geometry ({geom_types})")
    else:
        subscores["geometry"] = False
        feedback_parts.append(f"Incorrect geometry types: {geom_types}")

    # Criterion 4: Feature count ~8 (15 points)
    # Range 6-12 allows for some edge case variations in Voronoi calculation
    feat_count = result.get("feature_count", 0)
    if 6 <= feat_count <= 12:
        score += 15
        subscores["count"] = True
        feedback_parts.append(f"Feature count correct ({feat_count})")
    elif feat_count > 0:
        score += 8
        subscores["count"] = False
        feedback_parts.append(f"Feature count partial ({feat_count}, expected ~8)")
    else:
        subscores["count"] = False
        feedback_parts.append("No features found")

    # Criterion 5: Station attributes preserved (20 points)
    has_station_attrs = result.get("has_station_attributes", False)
    has_any_attrs = result.get("has_attributes", False)
    
    if has_station_attrs:
        score += 20
        subscores["attributes"] = True
        feedback_parts.append("Station attributes preserved")
    elif has_any_attrs:
        score += 10
        subscores["attributes"] = False
        feedback_parts.append("Generic attributes found, but station data missing/renamed")
    else:
        subscores["attributes"] = False
        feedback_parts.append("No attributes preserved")

    # Criterion 6: File freshness (Anti-gaming) (15 points)
    if result.get("created_after_task_start", False):
        score += 15
        subscores["freshness"] = True
        feedback_parts.append("File created during task")
    else:
        subscores["freshness"] = False
        feedback_parts.append("File creation timestamp predates task")

    # Final logic
    # Pass threshold is 55, but we enforce specific key criteria for "passed" boolean
    passed = score >= 55 and subscores.get("valid_geojson") and subscores.get("geometry")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }