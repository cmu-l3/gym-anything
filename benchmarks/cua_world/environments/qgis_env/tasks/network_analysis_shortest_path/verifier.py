#!/usr/bin/env python3
"""
Verifier for network_analysis_shortest_path task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_analysis_shortest_path(traj, env_info, task_info):
    """
    Verify the shortest path calculation.
    
    Scoring Criteria:
    1. Output file exists and is valid GeoJSON (20 pts)
    2. File was created during task (10 pts)
    3. Geometry is LineString/MultiLineString (10 pts)
    4. Path follows the diagonal (Optimal) route (40 pts)
       - Checked by distance to point (0.5, 0.5) being close to 0
    5. Path avoids the sub-optimal corner (20 pts)
       - Checked by distance to point (0.0, 1.0) being > 0.1
       
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    logger.info(f"Task Result: {result}")
    
    score = 0
    feedback = []
    
    # 1. File Existence and Validity (20 pts)
    if result.get('file_exists', False):
        analysis = result.get('geometry_analysis', {})
        if analysis.get('valid_geojson', False):
            score += 20
            feedback.append("Valid GeoJSON output found")
        else:
            feedback.append("Output file exists but is invalid GeoJSON")
    else:
        feedback.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Created during task (10 pts)
    if result.get('is_new', False):
        score += 10
        feedback.append("File created during task")
    else:
        feedback.append("File timestamp indicates it was not created during this session")
        
    # 3. Geometry Type (10 pts)
    gtype = analysis.get('geometry_type', '')
    if 'LineString' in gtype:
        score += 10
        feedback.append(f"Correct geometry type: {gtype}")
    else:
        feedback.append(f"Incorrect geometry type: {gtype} (expected LineString)")
        
    # 4. Correct Path Selection (Optimal) (40 pts)
    # Distance to diagonal midpoint (0.5, 0.5) should be very small (epsilon)
    dist_optimal = analysis.get('dist_to_optimal', float('inf'))
    if dist_optimal < 0.05: # Tolerance for floating point/snapping
        score += 40
        feedback.append("Route correctly follows the shortest diagonal path")
    else:
        feedback.append(f"Route deviates from optimal path (Dist: {dist_optimal:.4f})")
        
    # 5. Avoids Sub-optimal Path (20 pts)
    # Distance to corner (0.0, 1.0) should be large
    dist_avoid = analysis.get('dist_to_avoid', 0)
    if dist_avoid > 0.2:
        score += 20
        feedback.append("Route correctly avoids the longer path")
    else:
        feedback.append("Route passes through the sub-optimal corner")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }