#!/usr/bin/env python3
"""
Verifier for sakila_visual_model_evolution task.

Verifies:
1. Creation of .mwb model file.
2. Creation of 'customer_tier_history' table in live DB.
3. Correct column structure.
4. Existence of Foreign Key relationship to 'customer' table.
"""

import json
import tempfile
import os
import logging
import time

logger = logging.getLogger(__name__)

def verify_sakila_visual_model_evolution(traj, env_info, task_info):
    """
    Verify schema evolution task.

    Scoring (100 points):
    - Model File Created: 20 pts
    - Table Created in DB: 30 pts
    - Columns Correct: 20 pts
    - Foreign Key Exists: 30 pts

    Pass threshold: 70 points (Must have Table + FK essentially)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/model_evolution_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task likely failed to execute export script"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading verification result: {str(e)}"}

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)

    # 1. Verify Model File (20 pts)
    model_exists = result.get('model_exists', False)
    model_mtime = result.get('model_mtime', 0)
    
    if model_exists and model_mtime > task_start:
        score += 20
        feedback_parts.append("Model file created (20/20)")
    elif model_exists:
        # Existed before task start?
        score += 10
        feedback_parts.append("Model file exists but old timestamp (10/20)")
    else:
        feedback_parts.append("Model file not found (0/20)")

    # 2. Verify Table Creation (30 pts)
    table_exists = result.get('table_exists', 0) > 0
    if table_exists:
        score += 30
        feedback_parts.append("Table 'customer_tier_history' created (30/30)")
    else:
        feedback_parts.append("Table 'customer_tier_history' NOT found in DB (0/30)")

    # 3. Verify Columns (20 pts)
    # Expected 5 specific columns
    matching_cols = result.get('matching_cols_count', 0)
    if matching_cols == 5:
        score += 20
        feedback_parts.append("All columns defined correctly (20/20)")
    elif matching_cols > 0:
        partial_score = int((matching_cols / 5) * 20)
        score += partial_score
        missing = result.get('missing_cols', 'unknown')
        feedback_parts.append(f"Some columns missing ({missing}) ({partial_score}/20)")
    else:
        feedback_parts.append("No correct columns found (0/20)")

    # 4. Verify Foreign Key (30 pts)
    fk_exists = result.get('fk_exists', 0) > 0
    if fk_exists:
        score += 30
        feedback_parts.append("Foreign Key relationship verified (30/30)")
    else:
        feedback_parts.append("Foreign Key to 'customer' table NOT found (0/30)")

    # Pass logic
    # Need at least 70 points. This essentially requires the DB part to be mostly correct.
    # e.g. Table (30) + FK (30) + partial cols or model = Pass
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }