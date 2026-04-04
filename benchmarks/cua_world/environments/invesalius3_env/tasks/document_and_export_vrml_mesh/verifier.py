#!/usr/bin/env python3
"""
Verifier for document_and_export_vrml_mesh task.

Scoring (100 points total):
1. VRML File Created (30 pts): File exists and has valid VRML header.
2. Mesh Complexity (20 pts): VRML contains > 10,000 vertices (bona fide skull).
3. Info File Created (10 pts): Text file with number exists.
4. Data Consistency (40 pts): The reported vertex count in text file matches 
   the actual VRML vertex count within 1% tolerance.

Anti-gaming:
- Files must be created after task start time.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_document_and_export_vrml_mesh(traj, env_info, task_info):
    """
    Verify the agent exported a VRML model and correctly documented its vertex count.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_vertices = metadata.get('min_vertex_count', 10000)
    tolerance_percent = metadata.get('match_tolerance_percent', 1.0)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check Anti-Gaming
    if not result.get("files_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Files were not created during the task session (timestamps too old)."
        }

    # 1. VRML Creation (30 pts)
    vrml_exists = result.get("vrml_exists", False)
    vrml_header = result.get("vrml_valid_header", False)
    
    if vrml_exists and vrml_header:
        score += 30
        feedback_parts.append("Valid VRML file created")
    elif vrml_exists:
        score += 15
        feedback_parts.append("File exists but invalid VRML header")
    else:
        feedback_parts.append("VRML file not found")

    # 2. Mesh Complexity (20 pts)
    actual_count = result.get("vrml_vertex_count", 0)
    if actual_count >= min_vertices:
        score += 20
        feedback_parts.append(f"Mesh has realistic complexity ({actual_count:,} vertices)")
    else:
        feedback_parts.append(f"Mesh too simple or empty ({actual_count} vertices)")

    # 3. Info File Creation (10 pts)
    info_exists = result.get("info_exists", False)
    reported_count = result.get("info_reported_count", 0)
    
    if info_exists and reported_count > 0:
        score += 10
        feedback_parts.append(f"Info file contains count: {reported_count:,}")
    elif info_exists:
        score += 5
        feedback_parts.append("Info file exists but no valid number found")
    else:
        feedback_parts.append("Info file not found")

    # 4. Consistency Check (40 pts)
    # Check if reported count matches actual count within tolerance
    if info_exists and vrml_exists and actual_count > 0:
        diff = abs(reported_count - actual_count)
        percent_diff = (diff / actual_count) * 100.0
        
        if percent_diff <= tolerance_percent:
            score += 40
            feedback_parts.append(f"Reported count matches actual ({percent_diff:.2f}% diff)")
        else:
            feedback_parts.append(f"Reported count mismatches actual ({reported_count} vs {actual_count}, {percent_diff:.2f}% diff)")
    
    # Success threshold: Need valid file AND reasonable accuracy
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }