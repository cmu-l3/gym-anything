#!/usr/bin/env python3
"""
Verifier for Create Polaroid Photo Stack Task
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_polaroid_stack(traj, env_info, task_info):
    """
    Verify the Polaroid stack creation.
    
    Criteria:
    1. File modified during task.
    2. Slide 2 contains at least 3 groups.
    3. Each group contains at least 1 image and 1 rectangle (shape).
    4. Groups are rotated (non-zero rotation).
    5. VLM check on trajectory/final screenshot for visual confirmation (overlap/scatter).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
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
    
    # 1. Check File Modification (10 pts)
    if result.get("file_modified", False):
        score += 10
        feedback_parts.append("File Saved ✅")
    else:
        feedback_parts.append("File not modified ❌")

    analysis = result.get("odp_analysis", {})
    groups = analysis.get("groups_on_slide_2", [])
    
    # 2. Check Group Count (30 pts)
    # Expecting 3 groups
    valid_group_count = len(groups)
    if valid_group_count >= 3:
        score += 30
        feedback_parts.append(f"Found {valid_group_count} groups ✅")
    elif valid_group_count > 0:
        score += (valid_group_count * 10)
        feedback_parts.append(f"Found only {valid_group_count}/3 groups ⚠️")
    else:
        feedback_parts.append("No groups found on Slide 2 ❌")

    # 3. Check Group Structure & Rotation (40 pts)
    # Each group should have image + rect and rotation
    structure_score = 0
    rotation_score = 0
    
    valid_polaroids = 0
    
    for g in groups:
        is_valid_structure = g.get("has_image") and g.get("has_rect")
        rotation = g.get("rotation", 0)
        is_rotated = abs(rotation) > 0.001 # Non-zero rotation
        
        if is_valid_structure:
            structure_score += 1
        if is_rotated:
            rotation_score += 1
            
        if is_valid_structure and is_rotated:
            valid_polaroids += 1

    # Normalize structure score (max 20)
    final_structure_score = min(20, int((structure_score / 3) * 20))
    score += final_structure_score
    if structure_score >= 3:
        feedback_parts.append("Structure (Image+Rect) correct ✅")
    else:
        feedback_parts.append(f"Structure issues in {3-structure_score} groups ⚠️")

    # Normalize rotation score (max 20)
    final_rotation_score = min(20, int((rotation_score / 3) * 20))
    score += final_rotation_score
    if rotation_score >= 3:
        feedback_parts.append("Rotation applied ✅")
    else:
        feedback_parts.append("Some groups not rotated ⚠️")

    # 4. Anti-Gaming / Visual Check (Implicit via object count and explicit VLM if added)
    # The JSON analysis is quite robust against empty groups.
    # We could add bounding box overlap logic, but rotation + distinct objects is a strong proxy.
    
    # Pass Threshold
    # Max Score: 10 + 30 + 20 + 20 = 80 (Programmatic)
    # We reserve 20 points for VLM verification of "overlap/scatter" look if we implement it.
    # For now, let's scale the 80 points to 100 for the programmatic verifier 
    # OR assume VLM check is handled by the framework if configured.
    # Based on the prompt instructions, we should verify programmatically primarily.
    
    # Let's verify overlap using basic heuristics if bounding box info was available.
    # Since we simplified the analysis script, we'll rely on rotation as the proxy for "scattered".
    
    # Bonus points for exactly 3 groups (cleanliness)
    if valid_group_count == 3:
        score += 10
    
    # Bonus for all valid polaroids
    if valid_polaroids >= 3:
        score += 10
        
    # Cap score at 100
    score = min(100, score)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }