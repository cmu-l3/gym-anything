#!/usr/bin/env python3
"""
Verifier for add_farm_equipment task (Ekylibre).

Criteria:
1. Equipment Record Exists (40 pts): 'Massey Ferguson 7720' found in DB.
2. Work Number Correct (15 pts): 'MF-7720-01'.
3. Correct Variant/Nature (15 pts): Must be linked to tractor/equipment nature.
4. Product Count Increased (10 pts): General check for database state change.
5. Anti-Gaming Timestamp (5 pts): Record created during task execution.
6. VLM Workflow Verification (15 pts): Visual confirmation of UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_farm_equipment(traj, env_info, task_info):
    """
    Verifies the creation of the tractor equipment record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Massey Ferguson 7720")
    expected_work_number = metadata.get('expected_work_number', "MF-7720-01")
    nature_keywords = metadata.get('expected_nature_keywords', ["tractor", "tracteur", "equipment"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Database Verification (Primary)
    # ------------------------------------------------------------------
    record_found = result.get('record_found', False)
    record = result.get('record', {})
    
    # Check 1: Record Exists (40 pts)
    if record_found:
        score += 40
        feedback_parts.append("Equipment record found in database")
    else:
        feedback_parts.append("Equipment record NOT found")
    
    # Check 2: Work Number (15 pts)
    actual_work_num = record.get('work_number', '').strip()
    if record_found:
        if actual_work_num == expected_work_number:
            score += 15
            feedback_parts.append(f"Work number correct ({actual_work_num})")
        elif expected_work_number in actual_work_num:
            score += 10
            feedback_parts.append(f"Work number partial match ({actual_work_num})")
        else:
            feedback_parts.append(f"Work number incorrect (Expected: {expected_work_number}, Got: {actual_work_num})")

    # Check 3: Variant/Nature (15 pts)
    nature_name = record.get('nature_name', '').lower()
    nature_variety = record.get('nature_variety', '').lower()
    
    if record_found:
        is_valid_nature = any(k in nature_name for k in nature_keywords) or \
                          any(k in nature_variety for k in nature_keywords)
        
        if is_valid_nature:
            score += 15
            feedback_parts.append(f"Correct equipment type ({nature_name}/{nature_variety})")
        else:
            feedback_parts.append(f"Incorrect equipment type/nature ({nature_name}). Expected tractor/equipment.")

    # Check 4: Product Count Increase (10 pts)
    initial_count = int(result.get('initial_product_count', 0))
    final_count = int(result.get('final_product_count', 0))
    
    if final_count > initial_count:
        score += 10
        feedback_parts.append("Product count increased")
    else:
        feedback_parts.append("Product count did not increase")

    # Check 5: Anti-Gaming Timestamp (5 pts)
    task_start = int(result.get('task_start', 0))
    created_at = int(record.get('created_at', 0))
    
    if record_found and created_at >= task_start:
        score += 5
        feedback_parts.append("Record created during task session")
    elif record_found:
        feedback_parts.append("Record creation timestamp predates task start (Pre-existing data?)")

    # ------------------------------------------------------------------
    # 2. VLM Verification (Visual Confirmation) - 15 pts
    # ------------------------------------------------------------------
    # Use VLM to verify the agent actually interacted with the form
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if final_scr:
            frames.append(final_scr)
        
        if frames:
            prompt = """
            Review these screenshots of an agent using the Ekylibre farm software.
            The agent should be:
            1. Navigating to an Equipment or Production menu.
            2. Filling out a form to create a new tractor/equipment.
            3. Entering 'Massey Ferguson' or similar details.
            
            Does the visual history show the agent performing these actions?
            """
            
            vlm_response = query_vlm(images=frames, prompt=prompt).lower()
            
            if "yes" in vlm_response:
                score += 15
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM could not verify workflow visually")
        else:
            feedback_parts.append("No screenshots available for VLM check")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if DB checks are perfect, give partial VLM points to avoid punishing technical issues
        if score >= 80: 
            score += 10
            feedback_parts.append("VLM skipped, implicit pass based on DB success")

    # Final Calculation
    passed = score >= 60 and record_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }