#!/usr/bin/env python3
"""
Verifier for multi_tissue_stl_export task.

Scoring Criteria (100 points total):
1. Bone STL exists, is valid binary STL, and created during task (15 pts)
2. Bone STL has valid geometry (>10k triangles) (15 pts)
3. Skin STL exists, is valid binary STL, and created during task (15 pts)
4. Skin STL has valid geometry (>10k triangles) (15 pts)
5. Files are distinct (MD5 check) (10 pts)
6. Files represent different geometry (Triangle count diff > 10%) (15 pts)
7. Both files meet size threshold (>200KB) (10 pts)
8. Application state check (Implicit via file creation timestamps) (5 pts)

Pass Threshold: 60 points (Requires at least both files generated with some content)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_tissue_stl_export(traj, env_info, task_info):
    """
    Verify that two distinct STL files (Bone and Skin) were created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    bone_info = result.get("bone_stl", {})
    skin_info = result.get("skin_stl", {})
    
    # --- Check Bone STL (30 pts total) ---
    if bone_info.get("exists") and bone_info.get("is_binary_stl") and bone_info.get("created_during_task"):
        score += 15
        feedback_parts.append("Bone STL created")
        
        tris = bone_info.get("triangle_count", 0)
        if tris > 10000:
            score += 15
            feedback_parts.append(f"Bone geometry good ({tris} tris)")
        else:
            feedback_parts.append(f"Bone geometry too simple ({tris} tris)")
    else:
        feedback_parts.append("Bone STL missing/invalid")

    # --- Check Skin STL (30 pts total) ---
    if skin_info.get("exists") and skin_info.get("is_binary_stl") and skin_info.get("created_during_task"):
        score += 15
        feedback_parts.append("Skin STL created")
        
        tris = skin_info.get("triangle_count", 0)
        if tris > 10000:
            score += 15
            feedback_parts.append(f"Skin geometry good ({tris} tris)")
        else:
            feedback_parts.append(f"Skin geometry too simple ({tris} tris)")
    else:
        feedback_parts.append("Skin STL missing/invalid")

    # --- Check Distinction (25 pts total) ---
    if bone_info.get("exists") and skin_info.get("exists"):
        # Not identical files (anti-gaming: didn't just copy file)
        if result.get("files_are_distinct", False):
            score += 10
            feedback_parts.append("Files are distinct")
        else:
            feedback_parts.append("Files are identical (FAIL)")
            
        # Geometric distinction (different threshold = different tri count)
        bone_tris = bone_info.get("triangle_count", 0)
        skin_tris = skin_info.get("triangle_count", 0)
        
        if bone_tris > 0 and skin_tris > 0:
            # Calculate percent difference
            diff_percent = abs(bone_tris - skin_tris) / ((bone_tris + skin_tris) / 2) * 100
            if diff_percent > 10:
                score += 15
                feedback_parts.append("Surfaces show structural difference")
            else:
                feedback_parts.append(f"Surfaces too similar ({diff_percent:.1f}% diff)")
    
    # --- Check File Sizes (10 pts) ---
    size_pass = 0
    if bone_info.get("size_bytes", 0) > 200000: size_pass += 1
    if skin_info.get("size_bytes", 0) > 200000: size_pass += 1
    
    if size_pass == 2:
        score += 10
    elif size_pass == 1:
        score += 5
    
    # --- Timestamp / Execution Check (5 pts) ---
    # Given explicitly by "created_during_task" check in export script
    if bone_info.get("created_during_task") or skin_info.get("created_during_task"):
        score += 5

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }