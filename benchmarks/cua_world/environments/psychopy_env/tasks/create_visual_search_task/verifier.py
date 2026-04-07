#!/usr/bin/env python3
"""
Verifier for create_visual_search_task.

Verification Strategy (Programmatic + VLM):

1. Files Exist & Created (10 pts)
2. CSV Structure (20 pts):
   - Valid CSV
   - Required columns present (target_present, set_size)
   - Reasonable row count (>4)
3. Experiment Structure (20 pts):
   - Valid PsychoPy XML
   - At least 6 Text components (to support set size 6)
4. Code Logic (50 pts):
   - Code component exists (10 pts)
   - Randomization logic found (shuffle/random) (10 pts)
   - Position assignment logic found (.pos/setPos) (10 pts)
   - Visibility logic found (opacity/autoDraw) (10 pts)
   - Orientation logic found (ori/orientation) (10 pts)

Pass Threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_visual_search_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_visual_search_task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # Check Nonce
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        if expected_nonce and result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Nonce mismatch"}
    except:
        pass # Nonce check failed to run, proceed with caution

    score = 0
    feedback = []

    # 1. Files Check (10 pts)
    if result.get('exp_exists') and result.get('cond_exists'):
        if result.get('files_modified'):
            score += 10
            feedback.append("Files created successfully.")
        else:
            score += 5
            feedback.append("Files exist but not modified (old?).")
    else:
        feedback.append("Missing experiment or conditions file.")

    # 2. CSV Structure (20 pts)
    if result.get('cond_valid_csv'):
        if result.get('has_target_col') and result.get('has_setsize_col'):
            score += 15
            feedback.append("CSV columns correct.")
        else:
            feedback.append("CSV missing required columns (target_present/set_size).")
        
        if result.get('csv_row_count', 0) >= 4:
            score += 5
        else:
            feedback.append("CSV has too few rows.")

    # 3. Experiment Structure (20 pts)
    if result.get('exp_valid_xml'):
        score += 10
        # Check for enough components to support set size 6
        # A smart user might use 1 component + code loop, but standard Builder usage = 6 components
        if result.get('text_component_count', 0) >= 6:
            score += 10
            feedback.append(f"Found {result.get('text_component_count')} text components.")
        elif result.get('text_component_count', 0) >= 1:
            score += 5
            feedback.append("Found text components, but fewer than expected for set size 6.")
    else:
        feedback.append("Invalid Experiment XML.")

    # 4. Code Logic (50 pts)
    if result.get('has_code_component'):
        score += 10
        feedback.append("Code component found.")
        
        if result.get('has_random_import') or result.get('has_shuffle'):
            score += 10
            feedback.append("Randomization logic detected.")
        else:
            feedback.append("No randomization logic found.")
            
        if result.get('has_pos_assignment'):
            score += 10
            feedback.append("Position assignment logic detected.")
        else:
            feedback.append("No position assignment logic found.")
            
        if result.get('has_opacity_logic'):
            score += 10
            feedback.append("Visibility/SetSize logic detected.")
        else:
            feedback.append("No visibility logic found.")
            
        if result.get('has_orientation_logic'):
            score += 10
            feedback.append("Orientation logic detected.")
        else:
            feedback.append("No orientation logic found.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }