#!/usr/bin/env python3
"""
Verifier for create_floor_section task.

Criteria:
1. Floor "Patio" exists in DB (25 pts)
2. Floor count increased by 1 (10 pts)
3. Table 201 exists on Patio with capacity 4 (10 pts)
4. Table 202 exists on Patio with capacity 4 (10 pts)
5. Table 203 exists on Patio with capacity 4 (10 pts)
6. Exactly 3 tables on Patio (5 pts)
7. Visual verification (VLM) shows Patio/tables (30 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_floor_section(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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
    feedback = []

    # 2. Database Verification
    if result.get('floor_created', False):
        score += 25
        feedback.append("Floor 'Patio' created.")
    else:
        feedback.append("Floor 'Patio' NOT found in database.")

    floor_diff = result.get('floor_count_diff', 0)
    if floor_diff >= 1:
        score += 10
        feedback.append(f"Floor count increased (+{floor_diff}).")
    else:
        feedback.append("Floor count did not increase.")

    # Table checks
    t201 = result.get('table_201_correct', False)
    t202 = result.get('table_202_correct', False)
    t203 = result.get('table_203_correct', False)
    table_count = result.get('table_count', 0)

    if t201:
        score += 10
        feedback.append("Table 201 correct.")
    else:
        feedback.append("Table 201 missing or wrong capacity/floor.")

    if t202:
        score += 10
        feedback.append("Table 202 correct.")
    else:
        feedback.append("Table 202 missing or wrong capacity/floor.")

    if t203:
        score += 10
        feedback.append("Table 203 correct.")
    else:
        feedback.append("Table 203 missing or wrong capacity/floor.")

    if table_count == 3:
        score += 5
        feedback.append("Exactly 3 tables found on Patio.")
    elif table_count > 0:
        feedback.append(f"Found {table_count} tables on Patio (expected 3).")
    else:
        feedback.append("No tables found on Patio.")

    # 3. VLM Verification
    # Check if the UI shows the new section or tables
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this Floreant POS screenshot.
        Look for a floor section named "Patio" or tables numbered 201, 202, 203.
        
        Answer these questions:
        1. Is the text "Patio" visible (case-insensitive)?
        2. Are tables 201, 202, or 203 visible?
        3. Does this look like a POS floor plan or table management screen?
        
        Respond in JSON:
        {
            "patio_visible": boolean,
            "tables_visible": boolean,
            "is_pos_screen": boolean
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('patio_visible', False):
                vlm_score += 15
                feedback.append("VLM: 'Patio' label visible.")
            
            if parsed.get('tables_visible', False):
                vlm_score += 10
                feedback.append("VLM: New tables visible.")
                
            if parsed.get('is_pos_screen', False):
                vlm_score += 5
                
        except Exception as e:
            feedback.append(f"VLM verification failed: {e}")
            # Fallback: if DB checks passed perfectly, assume visual is likely okay 
            # or just award partial points if DB is perfect
            if score >= 70: 
                vlm_score = 15
                feedback.append("VLM failed, awarding partial points based on DB success.")
    
    score += vlm_score

    # Final Check
    passed = (score >= 60 and result.get('floor_created', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }