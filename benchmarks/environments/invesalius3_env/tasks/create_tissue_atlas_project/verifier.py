#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_tissue_atlas_project(traj, env_info, task_info):
    """
    Verifies that the agent created an InVesalius project with 3 specific masks.
    
    Scoring Breakdown (100 pts total):
    - File exists and is valid project: 10 pts
    - File created during task (anti-gaming): 5 pts
    - Exactly 3 masks found: 15 pts
    - Mask 'Dense_Bone' correct (name + threshold): 20 pts
    - Mask 'Spongy_Bone' correct (name + threshold): 20 pts
    - Mask 'Soft_Tissue' correct (name + threshold): 20 pts
    - Non-trivial data (file size check): 10 pts
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    # Get expected criteria from metadata
    metadata = task_info.get('metadata', {})
    expected_masks_criteria = metadata.get('expected_masks', [
        {"name": "Dense_Bone", "min_hu": 662, "max_hu": 3071, "tolerance": 50},
        {"name": "Spongy_Bone", "min_hu": 148, "max_hu": 661, "tolerance": 50},
        {"name": "Soft_Tissue", "min_hu": -700, "max_hu": 147, "tolerance": 50}
    ])
    
    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Check 1: File Validity (10 pts)
    if result.get("file_exists") and result.get("valid_project"):
        score += 10
        feedback_parts.append("Valid project file saved")
    else:
        return {"passed": False, "score": 0, "feedback": "Project file not found or invalid"}

    # Check 2: Anti-gaming (5 pts)
    if result.get("file_created_during_task"):
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session")

    # Check 3: Non-trivial data (10 pts)
    if result.get("file_size", 0) > 2048: # > 2KB implies some content
        score += 10
    else:
        feedback_parts.append("File size suspiciously small")

    # Check 4: Mask Count (15 pts)
    found_masks = result.get("masks", [])
    count = len(found_masks)
    if count == 3:
        score += 15
        feedback_parts.append("Exactly 3 masks found")
    else:
        feedback_parts.append(f"Found {count} masks (expected 3)")

    # Check 5: Verify Specific Masks (60 pts total)
    # Strategy: Look for best match for each expected mask
    for criteria in expected_masks_criteria:
        target_name = criteria["name"]
        t_min = criteria["min_hu"]
        t_max = criteria["max_hu"]
        tol = criteria["tolerance"]
        
        # Find mask with matching name
        match = next((m for m in found_masks if m["name"] == target_name), None)
        
        mask_points = 0
        if match:
            mask_points += 10 # Name match
            
            # Check Thresholds
            actual_min = match["thresh_min"]
            actual_max = match["thresh_max"]
            
            min_ok = abs(actual_min - t_min) <= tol
            max_ok = abs(actual_max - t_max) <= tol
            
            if min_ok and max_ok:
                mask_points += 10
                feedback_parts.append(f"Mask '{target_name}' correct")
            else:
                feedback_parts.append(f"Mask '{target_name}' found but thresholds mismatch (Expected: {t_min}-{t_max}, Got: {actual_min}-{actual_max})")
        else:
            feedback_parts.append(f"Mask '{target_name}' NOT found")
            
        score += mask_points

    # 4. Final Verdict
    passed = (score >= 70) and (count == 3) # Strict passing requires correct count and reasonable accuracy
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }