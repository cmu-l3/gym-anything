#!/usr/bin/env python3
"""
Verifier for spatial_join_summary_concatenation task.
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def verify_spatial_join_summary_concatenation(traj, env_info, task_info):
    """
    Verify the spatial summary join task.
    
    Criteria:
    1. Output file exists and is newly created.
    2. Output is valid GeoJSON Polygon layer (preserves precinct geometry).
    3. Output has correct feature count (2 precincts).
    4. Output contains summary fields (count and concatenation).
    5. Data content is correct (correct counts and text lists).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    analysis = result.get("analysis", {})
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (15 pts)
    if result.get("file_exists"):
        score += 15
        feedback.append("Output file found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    # Criterion 2: File Freshness (10 pts)
    if result.get("file_new"):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates pre-existing or stale data.")
        
    # Criterion 3: Valid Polygon GeoJSON (15 pts)
    if analysis.get("valid_geojson") and analysis.get("geom_type_polygon"):
        score += 15
        feedback.append("Valid Polygon GeoJSON.")
    else:
        feedback.append("Invalid format or geometry type (expected Polygons).")
        
    # Criterion 4: Feature Count (15 pts)
    # Should match precinct count (2)
    f_count = analysis.get("feature_count", 0)
    if f_count == 2:
        score += 15
        feedback.append("Correct feature count (2).")
    else:
        feedback.append(f"Incorrect feature count: {f_count} (expected 2).")
        
    # Criterion 5: Schema Check (Count & Concat fields) (20 pts)
    has_count = analysis.get("has_count_field")
    has_concat = analysis.get("has_concat_field")
    
    if has_count:
        score += 10
        feedback.append("Count summary field found.")
    if has_concat:
        score += 10
        feedback.append("Concatenation summary field found.")
    if not has_count and not has_concat:
        feedback.append("Missing summary fields.")
        
    # Criterion 6: Data Accuracy (25 pts)
    accuracy = analysis.get("data_accuracy", 0.0)
    if accuracy == 1.0:
        score += 25
        feedback.append("Data values (counts and names) are correct.")
    elif accuracy > 0.0:
        score += 10
        feedback.append("Some data values are correct, but errors found.")
    else:
        feedback.append("Data values incorrect (counts or concatenated names don't match).")
        
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }