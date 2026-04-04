#!/usr/bin/env python3
"""Verifier for create_sensor_network_layer task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_create_sensor_network_layer(traj, env_info, task_info):
    """
    Verify that the sensor network GeoPackage was created correctly.
    
    Scoring (100 points):
    - File exists and is valid GeoPackage: 15 pts
    - File created during task: 10 pts
    - Layer 'sensors' exists: 10 pts
    - CRS is EPSG:4326: 10 pts
    - Schema correct (model_id, install_year fields): 20 pts
    - Feature count is 1: 10 pts
    - Geometry is Point: 10 pts
    - Attribute values match (EnvSense-X1, 2024): 15 pts
    
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
    
    # 1. File existence and validity (15 pts)
    if result.get('file_exists', False) and analysis.get('valid_gpkg', False):
        score += 15
        subscores["file_valid"] = True
        feedback_parts.append("GeoPackage file created successfully")
    else:
        subscores["file_valid"] = False
        feedback_parts.append("GeoPackage file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File created during task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        subscores["fresh_file"] = True
        feedback_parts.append("File created during session")
    else:
        subscores["fresh_file"] = False
        feedback_parts.append("File timestamp indicates pre-existing file")
        
    # 3. Layer 'sensors' exists (10 pts)
    if analysis.get('has_sensors_layer', False):
        score += 10
        subscores["layer_exists"] = True
        feedback_parts.append("Layer 'sensors' found")
    else:
        subscores["layer_exists"] = False
        feedback_parts.append("Layer 'sensors' NOT found")
        # Critical failure for remaining checks
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    # 4. Geometry is Point (10 pts)
    if analysis.get('is_point', False):
        score += 10
        subscores["geometry_type"] = True
        feedback_parts.append("Geometry type is Point")
    else:
        subscores["geometry_type"] = False
        feedback_parts.append(f"Incorrect geometry type (code: {analysis.get('geometry_type_code')})")
        
    # 5. CRS is 4326 (10 pts)
    if analysis.get('is_4326', False):
        score += 10
        subscores["crs"] = True
        feedback_parts.append("CRS is EPSG:4326")
    else:
        subscores["crs"] = False
        feedback_parts.append(f"Incorrect CRS: {analysis.get('crs')}")
        
    # 6. Schema check (20 pts)
    fields = analysis.get('fields', {})
    has_model = analysis.get('has_model_id', False)
    has_year = analysis.get('has_install_year', False)
    
    schema_score = 0
    if has_model: schema_score += 10
    if has_year: schema_score += 10
    score += schema_score
    
    if schema_score == 20:
        subscores["schema"] = True
        feedback_parts.append("Schema fields correct")
    else:
        subscores["schema"] = False
        feedback_parts.append(f"Schema incomplete (found: {list(fields.keys())})")
        
    # 7. Feature Count (10 pts)
    count = analysis.get('feature_count', 0)
    if count == 1:
        score += 10
        subscores["count"] = True
        feedback_parts.append("Feature count correct (1)")
    else:
        subscores["count"] = False
        feedback_parts.append(f"Feature count incorrect: {count}")
        
    # 8. Attribute Values (15 pts)
    values = analysis.get('first_feature_values', {})
    val_model = values.get('model_id', '')
    val_year = values.get('install_year', 0)
    
    attr_score = 0
    # Loose match for string to handle potential casing or whitespace
    if val_model and "EnvSense-X1" in str(val_model): 
        attr_score += 8
    
    # Loose match for year (handle string '2024' or int 2024)
    if str(val_year) == "2024":
        attr_score += 7
        
    score += attr_score
    
    if attr_score == 15:
        subscores["attributes"] = True
        feedback_parts.append("Attribute values match")
    elif attr_score > 0:
        subscores["attributes"] = False
        feedback_parts.append(f"Partial attribute match: {values}")
    else:
        subscores["attributes"] = False
        feedback_parts.append("Attribute values do not match")
        
    passed = score >= 70 and subscores.get("file_valid", False) and subscores.get("layer_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }