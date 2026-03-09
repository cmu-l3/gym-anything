#!/usr/bin/env python3
"""
Verifier for merge_regional_vector_layers task.

Scoring Criteria:
1. Output file exists and is valid GeoJSON (20 pts)
2. File created during task (anti-gaming) (10 pts)
3. Feature count matches sum of inputs (30 pts)
4. Contains data from all 3 continents (20 pts)
5. Geometry types are correct (Polygon/MultiPolygon) (10 pts)
6. Attributes preserved (NAME, CONTINENT) (10 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_regional_vector_layers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # Extract analysis data
    analysis = result.get('analysis', {})
    
    # 1. File Exists & Valid (20 pts)
    if result.get('file_exists') and analysis.get('is_feature_collection'):
        score += 20
        feedback_parts.append("Valid GeoJSON output found")
    elif result.get('file_exists'):
        score += 10
        feedback_parts.append("Output file found but invalid format")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Created during task (10 pts)
    if result.get('created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File has old timestamp (pre-existing?)")

    # 3. Feature Count (30 pts)
    actual_count = analysis.get('feature_count', 0)
    expected_count = analysis.get('expected_count', 0)
    
    # Allow small tolerance (+/- 2) for potential QGIS artifacting or null geometries
    diff = abs(actual_count - expected_count)
    if expected_count > 0 and diff <= 2:
        score += 30
        feedback_parts.append(f"Feature count matches ({actual_count})")
    elif expected_count > 0 and diff <= 10:
        score += 15
        feedback_parts.append(f"Feature count close ({actual_count}/{expected_count})")
    else:
        feedback_parts.append(f"Feature count mismatch: got {actual_count}, expected ~{expected_count}")

    # 4. Continents Present (20 pts)
    continents = analysis.get('continents_present', [])
    required_continents = ['Europe', 'Africa', 'South America']
    found_continents = sum(1 for c in required_continents if c in continents)
    
    if found_continents == 3:
        score += 20
        feedback_parts.append("All 3 regions merged")
    elif found_continents > 0:
        pts = int((found_continents / 3) * 20)
        score += pts
        feedback_parts.append(f"Only {found_continents}/3 regions found")
    else:
        feedback_parts.append("No correct continent data found")

    # 5. Geometry Check (10 pts)
    geom_types = analysis.get('geometry_types', [])
    valid_types = {'Polygon', 'MultiPolygon'}
    if geom_types and all(g in valid_types for g in geom_types):
        score += 10
        feedback_parts.append("Geometries correct")
    elif geom_types:
        feedback_parts.append(f"Unexpected geometries: {geom_types}")

    # 6. Attributes Preserved (10 pts)
    attrs = analysis.get('attributes_found', [])
    if 'NAME' in attrs and 'CONTINENT' in attrs:
        score += 10
        feedback_parts.append("Attributes preserved")
    else:
        feedback_parts.append("Attributes missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }