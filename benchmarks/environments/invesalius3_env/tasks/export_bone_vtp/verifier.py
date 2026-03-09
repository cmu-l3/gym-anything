#!/usr/bin/env python3
"""
Verifier for export_bone_vtp task.

Scoring System (100 points total):
1. File Creation (30 pts):
   - File exists at correct path (15 pts)
   - File created/modified during task session (15 pts) [Anti-gaming]

2. File Format Validity (30 pts):
   - Valid VTP header detected (VTKFile type="PolyData") (15 pts)
   - Valid XML structure / File size > 100KB (15 pts)

3. Data Content/Quality (40 pts):
   - Vertex count > 5,000 (Non-trivial geometry) (20 pts)
   - Polygon count > 10,000 (Complete surface) (20 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_bone_vtp(traj, env_info, task_info):
    """Verify that the agent exported the cranial bone surface as VTP."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 102400) # 100KB
    min_points = metadata.get('min_points', 5000)
    min_polys = metadata.get('min_polys', 10000)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (30 pts) ---
    file_exists = result.get("file_exists", False)
    created_in_task = result.get("file_created_during_task", False)
    
    if file_exists:
        score += 15
        feedback_parts.append("File found at correct path")
        
        if created_in_task:
            score += 15
            feedback_parts.append("File created during session")
        else:
            feedback_parts.append("WARNING: File timestamp predates task start (reused file?)")
    else:
        feedback_parts.append("CRITICAL: Output file not found at /home/ga/Documents/cranial_bone.vtp")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: File Format (30 pts) ---
    is_vtp = result.get("is_vtp_format", False)
    file_size = result.get("file_size_bytes", 0)
    
    if is_vtp:
        score += 15
        feedback_parts.append("Valid VTK PolyData format detected")
    else:
        feedback_parts.append("Invalid format (Not recognized as VTP)")
        
    if file_size >= min_size:
        score += 15
        feedback_parts.append(f"File size OK ({file_size/1024:.1f} KB)")
    else:
        feedback_parts.append(f"File too small ({file_size} bytes)")

    # --- Criterion 3: Data Quality (40 pts) ---
    points = result.get("point_count", 0)
    polys = result.get("poly_count", 0)
    
    if points >= min_points:
        score += 20
        feedback_parts.append(f"Geometry OK ({points} vertices)")
    else:
        feedback_parts.append(f"Geometry too simple ({points} vertices < {min_points})")
        
    if polys >= min_polys:
        score += 20
        feedback_parts.append(f"Surface OK ({polys} polys)")
    else:
        feedback_parts.append(f"Surface incomplete ({polys} polys < {min_polys})")

    # 3. Final Evaluation
    # Pass if score >= 70 AND file exists AND is VTP
    passed = (score >= 70) and file_exists and is_vtp

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }