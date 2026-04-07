#!/usr/bin/env python3
"""
Verifier for macro_var_canada_analysis task.
"""

import json
import tempfile
import os
import logging
import csv

logger = logging.getLogger(__name__)

def verify_macro_var_canada(traj, env_info, task_info):
    """
    Verify VAR analysis task.
    
    Scoring:
    1. Setup & Script (20 pts): 'vars' installed, script modified, correct variable ordering.
    2. Lag Selection (20 pts): CSV exists, roughly correct format.
    3. Diagnostics (30 pts): CSV exists, contains Portmanteau and Granger results.
    4. IRF Plot (30 pts): PNG exists, substantial size.
    
    Note: Exact numeric verification of CSVs is omitted to be robust to minor R version differences,
    but file existence and keywords are checked.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Script & Setup (20 pts)
    if result.get('script_modified'):
        score += 5
        feedback.append("Script modified (+5)")
    else:
        feedback.append("Script not modified (0)")

    if result.get('has_vars_pkg'):
        score += 5
        feedback.append("vars package loaded (+5)")
    
    if result.get('has_correct_order'):
        score += 10
        feedback.append("Correct variable ordering found in script (+10)")
    else:
        feedback.append("Variable ordering 'prod, e, U, rw' not explicitly found in script (0)")

    # 2. Lag Selection (20 pts)
    if result.get('sel_exists') and result.get('sel_new'):
        score += 10
        feedback.append("Selection CSV created (+10)")
        if result.get('sel_rows', 0) > 0:
            score += 10
            feedback.append("Selection CSV has content (+10)")
    else:
        feedback.append("Selection CSV missing/old (0)")

    # 3. Diagnostics (30 pts)
    if result.get('diag_exists') and result.get('diag_new'):
        score += 10
        feedback.append("Diagnostics CSV created (+10)")
        if result.get('has_portmanteau'):
            score += 10
            feedback.append("Portmanteau test found (+10)")
        if result.get('has_granger'):
            score += 10
            feedback.append("Granger test found (+10)")
    else:
        feedback.append("Diagnostics CSV missing/old (0)")

    # 4. IRF Plot (30 pts)
    if result.get('irf_exists') and result.get('irf_new'):
        irf_size = result.get('irf_size', 0)
        if irf_size > 10000: # >10KB
            score += 30
            feedback.append("IRF Plot created and valid size (+30)")
        elif irf_size > 0:
            score += 15
            feedback.append("IRF Plot created but small (+15)")
    else:
        feedback.append("IRF Plot missing (0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }