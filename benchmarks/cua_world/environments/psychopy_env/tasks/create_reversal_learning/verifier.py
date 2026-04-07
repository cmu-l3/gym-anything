#!/usr/bin/env python3
"""
Verifier for create_reversal_learning task.

Scoring Breakdown:
1. CSV File (35 pts):
   - Exists & Modified (10)
   - Correct Columns (10)
   - Balanced/40 rows (15)
2. Experiment Structure (30 pts):
   - Exists & Modified (10)
   - Routines correct (10)
   - Loop connected to CSV (5)
   - Mouse component (5)
3. Logic & Code (35 pts):
   - Code component exists (10)
   - Implements random/probabilistic logic (10)
   - Implements reversal criterion (8) (10)
   - Logs required data (5)

Total: 100
Pass: 70
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_reversal_learning(traj, env_info, task_info):
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
        copy_from_env("/tmp/reversal_learning_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. CSV Verification
    if result.get("cond_exists") and result.get("cond_modified"):
        score += 10
        feedback_parts.append("Conditions file created")
        
        # Columns
        req_cols = ["left_color", "right_color", "corr_ans"]
        actual_cols = result.get("csv_cols", [])
        if all(c in actual_cols for c in req_cols):
            score += 10
            feedback_parts.append("CSV columns correct")
        else:
            feedback_parts.append(f"Missing CSV columns (Found: {actual_cols})")
            
        # Structure
        if result.get("csv_rows") == 40 and result.get("csv_balanced"):
            score += 15
            feedback_parts.append("CSV rows balanced (40)")
        elif result.get("csv_rows") == 40:
            score += 5
            feedback_parts.append("CSV has 40 rows but unbalanced")
        else:
             feedback_parts.append(f"CSV row count incorrect: {result.get('csv_rows')}")
    else:
        feedback_parts.append("Conditions file missing or not modified")

    # 2. Experiment Structure Verification
    if result.get("exp_exists") and result.get("exp_modified"):
        score += 10
        
        if result.get("has_routines"):
            score += 10
            feedback_parts.append("Routines correct")
        else:
            feedback_parts.append("Missing required routines")
            
        if result.get("loop_uses_csv"):
            score += 5
            feedback_parts.append("Loop connected")
        
        if result.get("has_mouse"):
            score += 5
            feedback_parts.append("Mouse component found")
    else:
        feedback_parts.append("Experiment file missing")

    # 3. Logic Verification
    if result.get("has_code_component"):
        score += 10
        feedback_parts.append("Code component exists")
        
        if result.get("code_uses_random"):
            score += 10
            feedback_parts.append("Probabilistic logic found")
            
        if result.get("code_checks_criterion"):
            score += 10
            feedback_parts.append("Reversal criterion (8) found")
            
        if result.get("code_logs_data"):
            score += 5
            feedback_parts.append("Data logging found")
    else:
        feedback_parts.append("No code component found")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }