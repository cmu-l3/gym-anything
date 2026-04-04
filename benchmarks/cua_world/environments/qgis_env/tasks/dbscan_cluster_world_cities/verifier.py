#!/usr/bin/env python3
"""
Verifier for dbscan_cluster_world_cities task.

Checks:
1. Output file exists and was created during task.
2. Output is valid GeoJSON.
3. Feature count is reasonable (~243 for Natural Earth populated places).
4. Attributes contain a cluster ID field.
5. Clustering actually happened (multiple clusters found).
6. Noise points detected (DBSCAN usually finds noise in global city data).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dbscan_cluster_world_cities(traj, env_info, task_info):
    """
    Verify DBSCAN clustering task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Task result: {result}")

    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (10 pts)
    if result.get('file_exists', False):
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File Validity (10 pts)
    if analysis.get('valid', False):
        score += 10
    else:
        feedback_parts.append("Output is not valid GeoJSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Feature Count (15 pts)
    # Natural Earth 110m populated places has ~243 features. Allow range.
    count = analysis.get('feature_count', 0)
    if 200 <= count <= 300:
        score += 15
        feedback_parts.append(f"Feature count correct ({count})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Feature count atypical ({count})")
    else:
        feedback_parts.append("File contains no features")

    # Criterion 4: Cluster ID Field (20 pts)
    if analysis.get('has_cluster_field', False):
        score += 20
        field_name = analysis.get('cluster_field_name', 'unknown')
        feedback_parts.append(f"Cluster field found ('{field_name}')")
    else:
        feedback_parts.append("No cluster ID field found in output")

    # Criterion 5: Multiple Clusters Found (20 pts)
    # DBSCAN on global cities with eps=5 should find several clusters (Europe, East Asia, etc.)
    distinct_clusters = analysis.get('distinct_cluster_count', 0)
    if distinct_clusters >= 3:
        score += 20
        feedback_parts.append(f"Found {distinct_clusters} distinct clusters")
    elif distinct_clusters > 1:
        score += 10
        feedback_parts.append(f"Only {distinct_clusters} clusters found (expected >2)")
    else:
        feedback_parts.append("Clustering failed (all points in one group or noise)")

    # Criterion 6: Noise Points Exist (10 pts)
    # Some cities should be isolated
    if analysis.get('has_noise', False):
        score += 10
        feedback_parts.append("Noise points detected")
    else:
        feedback_parts.append("No noise points detected (everything clustered)")

    # Criterion 7: Original Attributes Preserved (10 pts)
    if analysis.get('has_original_attributes', False):
        score += 10
        feedback_parts.append("Original attributes preserved")
    else:
        feedback_parts.append("Original attributes missing")

    # Criterion 8: File Freshness (5 pts)
    if result.get('file_created_during_task', False):
        score += 5
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session")

    # Calculate Pass/Fail
    # Passing requires > 60 points AND valid file AND cluster field
    critical_success = (result.get('file_exists') and 
                        analysis.get('valid') and 
                        analysis.get('has_cluster_field'))
                        
    passed = (score >= 60) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }