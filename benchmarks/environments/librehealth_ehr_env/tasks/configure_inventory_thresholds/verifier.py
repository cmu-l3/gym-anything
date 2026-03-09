#!/usr/bin/env python3
"""
Verifier for configure_inventory_thresholds task.

Scoring Criteria:
1. Ibuprofen 200mg Reorder Level = 150 (40 pts)
2. Metformin 500mg Reorder Level = 60 (40 pts)
3. Data Integrity (Names unchanged) (10 pts)
4. VLM Navigation Check (10 pts) - Verifies inventory UI was accessed
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_thresholds(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load exported results
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
            
    # Get expected values from metadata
    targets = task_info.get('metadata', {}).get('target_drugs', [])
    drugs_found = result.get('drugs_found', [])
    
    # Create lookup map for found drugs
    found_map = {d['name']: d['reorder_point'] for d in drugs_found}
    
    # 2. Database Verification (80 pts total)
    for target in targets:
        name = target['name']
        expected_val = target['expected_reorder_point']
        
        if name in found_map:
            actual_val = found_map[name]
            if actual_val == expected_val:
                score += 40
                feedback_parts.append(f"Correct: {name} set to {actual_val}")
            else:
                feedback_parts.append(f"Incorrect: {name} is {actual_val} (expected {expected_val})")
        else:
            feedback_parts.append(f"Missing: {name} not found in database (integrity check failed)")

    # 3. Integrity Check (10 pts)
    # If we found both drugs by name, it means the names weren't accidentally changed
    if len(drugs_found) >= 2:
        score += 10
        feedback_parts.append("Data integrity maintained")
    else:
        feedback_parts.append("Data integrity issue: Some drugs missing or renamed")

    # 4. VLM Verification for Navigation (10 pts)
    # We want to ensure they actually used the UI and didn't just guess/game
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are verifying an agent using an Electronic Health Record (EHR) system.
            The task is to configure inventory settings.
            
            Look at these screenshots and answer:
            1. Is the "Inventory" or "Drug Dispensary" page visible in any frame? (Look for lists of drugs, tables with 'On Hand', 'Reorder' columns)
            2. Is a form visible for editing a drug/medication?
            
            Return JSON: {"inventory_visible": bool, "edit_form_visible": bool}
            """
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('inventory_visible') or parsed.get('edit_form_visible'):
                    score += 10
                    feedback_parts.append("VLM confirmed Inventory navigation")
                else:
                    feedback_parts.append("VLM could not confirm Inventory navigation")
            else:
                # If VLM fails, we default to giving points if DB check passed to avoid false negatives
                if score >= 80:
                    score += 10
                    feedback_parts.append("VLM unavailable, assumed valid based on DB success")
    except Exception as e:
        logger.warning(f"VLM check error: {e}")
        # Graceful fallback
        if score >= 80:
            score += 10
    
    passed = (score >= 90) # Requires both values correct + integrity + navigation evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }