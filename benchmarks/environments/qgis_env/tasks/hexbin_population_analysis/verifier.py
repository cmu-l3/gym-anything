#!/usr/bin/env python3
"""
Verifier for hexbin_population_analysis task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hexbin_population_analysis(traj, env_info, task_info):
    """
    Verify that the agent performed the hexbin analysis correctly.
    
    Scoring Criteria (100 points total):
    - File Exists: 10 pts
    - Valid GeoJSON: 10 pts
    - Polygon Geometry: 10 pts
    - Hexagonal Shape (>80% features): 10 pts
    - Plausible Feature Count (15-400): 10 pts
    - Count Field Present: 10 pts
    - Population Field Present: 15 pts
    - Population Values Plausible (>50M total): 10 pts
    - Features in Europe (>80%): 10 pts
    - File is New: 5 pts
    
    Pass Threshold: 60 points
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
    
    # 1. File Exists (10)
    if result.get('file_exists'):
        score += 10
        subscores['file_exists'] = True
        feedback_parts.append("Output file found")
    else:
        subscores['file_exists'] = False
        feedback_parts.append("Output file NOT found")
        # Fail early if no file
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid GeoJSON (10)
    if analysis.get('valid'):
        score += 10
        subscores['valid_geojson'] = True
    else:
        feedback_parts.append("Invalid GeoJSON structure")
        
    # 3. Polygon Geometry (10)
    if analysis.get('all_polygons'):
        score += 10
        subscores['all_polygons'] = True
        feedback_parts.append("Features are polygons")
    else:
        feedback_parts.append("Features are not all polygons")
        
    # 4. Hexagonal Shape (10)
    # Heuristic: verify coordinate count matches hexagon
    if analysis.get('hex_shape_ratio', 0) > 0.8:
        score += 10
        subscores['hex_shape'] = True
        feedback_parts.append("Geometries appear to be hexagonal")
    else:
        feedback_parts.append("Geometries do not resemble hexagons")
        
    # 5. Plausible Feature Count (10)
    # Europe hex grid at ~3 deg spacing should have roughly 30-100 cells depending on bounding box fit and filtering
    count = analysis.get('feature_count', 0)
    if 15 <= count <= 400:
        score += 10
        subscores['feature_count'] = True
        feedback_parts.append(f"Feature count plausible ({count})")
    else:
        feedback_parts.append(f"Feature count implausible ({count})")
        
    # 6. Count Field (10)
    if analysis.get('has_count_field'):
        score += 10
        subscores['has_count_field'] = True
    else:
        feedback_parts.append("City count field missing")
        
    # 7. Population Field (15)
    if analysis.get('has_pop_field'):
        score += 15
        subscores['has_pop_field'] = True
    else:
        feedback_parts.append("Population sum field missing")
        
    # 8. Population Values (10)
    # Total pop of Europe is ~750M. Populated places dataset subset might be less, 
    # but certainly > 50M.
    total_pop = analysis.get('total_population_sum', 0)
    if total_pop > 50000000:
        score += 10
        subscores['pop_plausible'] = True
        feedback_parts.append("Population sums plausible")
    else:
        feedback_parts.append(f"Total population sum too low ({total_pop})")
        
    # 9. Features in Europe (10)
    if analysis.get('europe_centroid_ratio', 0) > 0.8:
        score += 10
        subscores['spatial_location'] = True
        feedback_parts.append("Features located in Europe")
    else:
        feedback_parts.append("Features spatially outside target area")
        
    # 10. File is New (5)
    if result.get('is_new_file'):
        score += 5
        subscores['is_new'] = True
    else:
        feedback_parts.append("Output file timestamp not updated")
        
    passed = score >= 60 and subscores.get('file_exists') and subscores.get('valid_geojson')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }