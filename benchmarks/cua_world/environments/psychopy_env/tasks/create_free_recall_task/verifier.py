#!/usr/bin/env python3
"""
Verifier for create_free_recall_task.

Verification Strategy:
1. Validates `word_list.csv`: Must exist, contain 15 specific words.
2. Validates `free_recall.psyexp`:
   - Must contain 'study' and 'recall' routines.
   - 'study' routine must be inside a loop referencing the CSV.
   - 'recall' routine must contain an Editable TextBox component.
   - 'recall' routine should ideally be outside the study loop.

Scoring:
- Files Exist: 10 pts
- Word List Valid: 20 pts
- Study Loop Correct: 20 pts
- TextBox Component: 30 pts
- Editable Config: 20 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_free_recall_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/free_recall_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 1. File Existence & timestamps (10 pts)
    files_ok = (result.get('exp_file_exists') and 
                result.get('csv_file_exists') and 
                result.get('exp_file_modified'))
    
    if files_ok:
        score += 10
        feedback_parts.append("Files created successfully.")
    else:
        feedback_parts.append("Missing required files.")

    # 2. Word List Validation (20 pts)
    if result.get('csv_words_match'):
        score += 20
        feedback_parts.append("Word list content matches targets.")
    elif result.get('csv_word_count') >= 15:
        score += 10
        feedback_parts.append("Word list has correct length but content differs.")
    else:
        missing = result.get('csv_missing_words', [])
        feedback_parts.append(f"Word list invalid. Missing: {missing[:3]}...")

    # 3. Study Loop Structure (20 pts)
    # Requirements: Has loop, loop refs CSV, study routine is IN loop
    loop_ok = False
    if result.get('has_loop') and result.get('study_in_loop'):
        # Check if CSV reference looks correct (contains 'word_list' or 'csv')
        ref = result.get('loop_file_ref', '')
        if 'word_list' in ref or '.csv' in ref:
            loop_ok = True
    
    if loop_ok:
        score += 20
        feedback_parts.append("Study loop configured correctly.")
    else:
        feedback_parts.append("Study loop missing or misconfigured.")

    # 4. TextBox Usage (30 pts)
    # Requirements: Recall routine exists, has TextBox component
    if result.get('has_recall_routine') and result.get('has_textbox_component'):
        score += 30
        feedback_parts.append("Recall routine has TextBox component.")
    elif result.get('has_recall_routine'):
        feedback_parts.append("Recall routine exists but missing TextBox.")
    else:
        feedback_parts.append("Recall routine missing.")

    # 5. Editable Configuration (20 pts)
    # Requirements: TextBox is set to editable
    if result.get('textbox_is_editable'):
        score += 20
        feedback_parts.append("TextBox is correctly set to Editable.")
    else:
        if result.get('has_textbox_component'):
            feedback_parts.append("TextBox exists but is NOT Editable.")

    # Check for structural error (Recall inside loop) - Penalty only? 
    # Or strict check? The prompt implied strict flow control.
    # If recall is INSIDE loop, it's a major logic error for Free Recall.
    # Let's deduct 10 points if recall is inside loop, but don't fail just for that.
    if not result.get('recall_outside_loop'):
        score = max(0, score - 10)
        feedback_parts.append("Warning: Recall routine is inside the loop (logic error).")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }