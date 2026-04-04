#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_params_bone_surface(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created a project with a custom mask threshold (350-2000).
    2. Generated a 3D surface.
    3. Exported a valid STL.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    target_min = metadata.get('target_threshold_min', 350)
    target_max = metadata.get('target_threshold_max', 2000)
    tol = metadata.get('threshold_tolerance', 10)
    min_tris = metadata.get('min_triangles', 5000)
    max_tris = metadata.get('max_triangles', 400000)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Project Existence & Validity (20 pts)
    if result.get('project_exists') and result.get('project_valid'):
        score += 15
        feedback_parts.append("Valid project file saved")
    elif result.get('project_exists'):
        score += 5
        feedback_parts.append("Project file exists but invalid/corrupt")
    else:
        feedback_parts.append("Project file not found")

    # 2. Check Mask Thresholds (35 pts)
    # We look for ANY mask that matches the criteria
    masks = result.get('masks', [])
    mask_match = False
    best_mask_score = 0
    
    if not masks:
        feedback_parts.append("No segmentation masks found in project")
    else:
        for m in masks:
            current_mask_score = 0
            t_min = m.get('threshold_min', -9999)
            t_max = m.get('threshold_max', -9999)
            
            # Check lower bound
            if abs(t_min - target_min) <= tol:
                current_mask_score += 15
            elif abs(t_min - 226) <= 5: # Caught using standard Bone preset
                current_mask_score -= 5 # Penalize slightly or just don't award
            
            # Check upper bound
            if abs(t_max - target_max) <= tol:
                current_mask_score += 15
            
            # Bonus for not being a standard preset (Simple check: neither 226 nor 3071)
            if abs(t_min - 226) > 5 and abs(t_max - 3071) > 5:
                current_mask_score += 5
                
            if current_mask_score > best_mask_score:
                best_mask_score = current_mask_score
                
        score += best_mask_score
        if best_mask_score >= 30:
            mask_match = True
            feedback_parts.append(f"Custom threshold mask found ({target_min}-{target_max} HU)")
        elif best_mask_score > 0:
            feedback_parts.append("Mask found but thresholds only partially match")
        else:
            feedback_parts.append("Masks found but incorrect thresholds (likely used default presets)")

    # 3. Check Surface Generation in Project (10 pts)
    if result.get('surfaces_in_project', 0) > 0:
        score += 10
        feedback_parts.append("Surface generated in project")
    else:
        feedback_parts.append("No surface saved in project")

    # 4. Check STL Export (35 pts)
    stl_valid = result.get('stl_valid', False)
    stl_tris = result.get('stl_triangle_count', 0)
    
    if result.get('stl_exists'):
        if stl_valid:
            score += 10
            feedback_parts.append("Valid STL exported")
            
            # Triangle count check (Cortical bone with 'keep largest' should be cleaner than raw bone)
            if min_tris <= stl_tris <= max_tris:
                score += 15
                feedback_parts.append(f"Triangle count OK ({stl_tris})")
            else:
                feedback_parts.append(f"Triangle count out of range ({stl_tris}) - expected {min_tris}-{max_tris}")
            
            # File size check (sanity check)
            if result.get('stl_size_bytes', 0) > 100000:
                score += 10
            else:
                feedback_parts.append("STL file suspiciously small")
        else:
            score += 5
            feedback_parts.append("STL file exists but is invalid")
    else:
        feedback_parts.append("STL output not found")

    # Anti-gaming check
    if not result.get('files_created_during_task', False):
        score = 0
        feedback_parts.append("CRITICAL: Output files not created during task session")

    # Success logic: Need reasonable score AND key files present
    passed = (score >= 70) and mask_match and result.get('stl_valid')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }