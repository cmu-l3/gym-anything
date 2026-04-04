#!/usr/bin/env python3
"""
Verifier for package_layers_geopackage task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_package_layers_geopackage(traj, env_info, task_info):
    """
    Verify that the agent consolidated 3 layers into a single GeoPackage.

    Scoring (100 points total):
    - 15 pts: GeoPackage file exists
    - 15 pts: GeoPackage created during task (anti-gaming)
    - 10 pts: Valid SQLite/GeoPackage structure
    - 20 pts: Contains 3 distinct layers
    - 15 pts: Layer names are correct (zones, stations, roads)
    - 15 pts: Feature counts match (2 polygons, 3 points, 2 lines)
    - 10 pts: QGIS project file saved

    Pass threshold: 55 points (Must at least create a valid GPKG with some data)
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
    
    # 1. GeoPackage exists (15 pts)
    if result.get("gpkg_exists"):
        score += 15
        feedback_parts.append("GeoPackage file created")
    else:
        feedback_parts.append("GeoPackage file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Created during task (15 pts)
    if result.get("gpkg_created_after_task_start"):
        score += 15
        feedback_parts.append("File timestamp valid")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing?)")

    # 3. Valid Structure (10 pts)
    if result.get("gpkg_valid_sqlite") and result.get("gpkg_has_contents_table"):
        score += 10
        feedback_parts.append("Valid GeoPackage structure")
    else:
        feedback_parts.append("Invalid or corrupted GeoPackage")

    # 4. Layer Count (20 pts)
    layers = result.get("gpkg_layers", [])
    layer_count = len(layers)
    if layer_count >= 3:
        score += 20
        feedback_parts.append(f"Found {layer_count} layers")
    elif layer_count > 0:
        score += (layer_count * 5) # Partial credit
        feedback_parts.append(f"Found {layer_count} layers (expected 3)")
    else:
        feedback_parts.append("No layers found in GeoPackage")

    # 5. Layer Names (15 pts) - 5 pts each
    expected_names = ["zones", "stations", "roads"]
    found_names = [l.lower() for l in layers]
    name_score = 0
    for name in expected_names:
        if name in found_names:
            name_score += 5
    score += name_score
    if name_score == 15:
        feedback_parts.append("All layer names correct")
    elif name_score > 0:
        feedback_parts.append(f"Some layer names correct ({name_score}/15)")
    else:
        feedback_parts.append("Layer names incorrect (expected 'zones', 'stations', 'roads')")

    # 6. Content/Feature Counts (15 pts) - 5 pts each correct layer count
    details = result.get("gpkg_layer_details", {})
    content_score = 0
    
    # Check zones (2 features)
    if "zones" in details and details["zones"].get("count") == 2:
        content_score += 5
    elif any(d.get("count") == 2 and "polygon" in d.get("geom_type", "").lower() for d in details.values()):
        # Fallback if name is wrong but content seems right
        content_score += 2

    # Check stations (3 features)
    if "stations" in details and details["stations"].get("count") == 3:
        content_score += 5
    elif any(d.get("count") == 3 and "point" in d.get("geom_type", "").lower() for d in details.values()):
        content_score += 2

    # Check roads (2 features)
    if "roads" in details and details["roads"].get("count") == 2:
        content_score += 5
    elif any(d.get("count") == 2 and "line" in d.get("geom_type", "").lower() for d in details.values()):
        content_score += 2
    
    score += content_score
    if content_score > 0:
        feedback_parts.append("Layer content verified")

    # 7. Project Saved (10 pts)
    if result.get("project_exists"):
        score += 10
        feedback_parts.append("QGIS project saved")
    else:
        feedback_parts.append("QGIS project NOT saved")

    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }