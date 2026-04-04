#!/usr/bin/env python3
"""
Verifier for simplify_geometries_web_export task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_simplify_geometries_web_export(traj, env_info, task_info):
    """
    Verify that country boundaries were simplified and exported correctly.
    
    Scoring (100 points):
    - Output file exists: 10 points
    - Valid GeoJSON format: 15 points
    - File created during task: 10 points
    - Features preserved (>200 countries): 20 points
    - Geometry type is Polygon/MultiPolygon: 10 points
    - Vertex reduction achieved (>30% reduction): 25 points
    - Non-trivial file content (>10KB): 10 points
    
    Pass threshold: 60 points
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
    input_vertex_count = result.get('input_vertex_count', 58000)
    if input_vertex_count == 0: input_vertex_count = 58000  # Fallback
    
    # Criterion 1: File exists (10 pts)
    if result.get('file_exists', False):
        score += 10
        subscores["file_exists"] = True
        feedback_parts.append("Output file found")
    else:
        subscores["file_exists"] = False
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Criterion 2: Valid GeoJSON (15 pts)
    if analysis.get('valid', False):
        score += 15
        subscores["valid_json"] = True
        feedback_parts.append("Valid GeoJSON")
    else:
        subscores["valid_json"] = False
        feedback_parts.append("Invalid or unreadable GeoJSON")
        
    # Criterion 3: File created during task (10 pts)
    if result.get('is_new', False):
        score += 10
        subscores["is_new"] = True
        feedback_parts.append("File created during task")
    else:
        subscores["is_new"] = False
        feedback_parts.append("File timestamp indicates pre-existing file")
        
    # Criterion 4: Feature count preserved (20 pts)
    # Original dataset has ~241 features. Simplification might remove tiny islands.
    feature_count = analysis.get('feature_count', 0)
    if feature_count >= 200:
        score += 20
        subscores["feature_count"] = True
        feedback_parts.append(f"Feature count preserved ({feature_count})")
    elif feature_count > 0:
        # Partial credit if some features exist but many lost
        score += 10
        subscores["feature_count"] = False
        feedback_parts.append(f"Significant feature loss ({feature_count} remaining)")
    else:
        subscores["feature_count"] = False
        feedback_parts.append("No features in output")
        
    # Criterion 5: Geometry type check (10 pts)
    poly_count = analysis.get('polygon_count', 0)
    invalid_count = analysis.get('invalid_geom_count', 0)
    if poly_count > 0 and invalid_count == 0:
        score += 10
        subscores["geom_type"] = True
        feedback_parts.append("Geometries are valid Polygons/MultiPolygons")
    else:
        subscores["geom_type"] = False
        feedback_parts.append(f"Geometry issues: {poly_count} polygons, {invalid_count} other/invalid")
        
    # Criterion 6: Vertex reduction (25 pts)
    output_vertex_count = analysis.get('vertex_count', 0)
    if output_vertex_count > 0:
        ratio = output_vertex_count / input_vertex_count
        reduction_percent = (1.0 - ratio) * 100
        
        if reduction_percent >= 30:
            score += 25
            subscores["simplification"] = True
            feedback_parts.append(f"Simplification successful ({int(reduction_percent)}% reduction)")
        elif reduction_percent > 5:
            score += 10
            subscores["simplification"] = False
            feedback_parts.append(f"Minor simplification ({int(reduction_percent)}% reduction) - target >30%")
        else:
            subscores["simplification"] = False
            feedback_parts.append(f"No significant simplification detected ({int(reduction_percent)}% reduction)")
            
        feedback_parts.append(f"Vertices: {input_vertex_count} -> {output_vertex_count}")
    else:
        subscores["simplification"] = False
        feedback_parts.append("No vertices found to analyze")

    # Criterion 7: Non-trivial content (10 pts)
    file_size = result.get('file_size_bytes', 0)
    if file_size > 10240: # > 10KB
        score += 10
        subscores["content_size"] = True
        feedback_parts.append(f"File size valid ({int(file_size/1024)}KB)")
    else:
        subscores["content_size"] = False
        feedback_parts.append("File too small/empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }