#!/usr/bin/env python3
"""
Verifier for chinook_inventory_lifecycle_management task.

Scoring Criteria:
1. Schema Modification (20 pts): 'IsArchived' exists, correct type/default.
2. Update Precision (30 pts): No active tracks (sold in 2013) were flagged.
3. Update Recall (30 pts): Dead tracks (not sold in 2013) WERE flagged.
4. Report Generation (20 pts): CSV exists and is valid.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_lifecycle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/safe_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Schema Check (20 pts)
    schema_correct = result.get('schema_correct', False)
    col_type = result.get('column_type', '').lower()
    default_val = str(result.get('default_value', '')).strip()

    if schema_correct:
        score += 10
        feedback.append("Column 'IsArchived' exists (10/10)")
        
        # Type check (INTEGER)
        if 'int' in col_type:
            score += 5
            feedback.append(f"Column type '{col_type}' is correct (5/5)")
        else:
            feedback.append(f"Column type '{col_type}' is incorrect, expected INTEGER (0/5)")
            
        # Default value check (0)
        if default_val == '0':
            score += 5
            feedback.append("Default value is 0 (5/5)")
        else:
            feedback.append(f"Default value is '{default_val}', expected 0 (0/5)")
    else:
        feedback.append("Column 'IsArchived' not found in table 'tracks' (0/20)")

    # 2. Update Precision (30 pts)
    # Did we accidentally archive things that shouldn't be?
    mistakes = result.get('active_mistakenly_archived', 0)
    precision = result.get('update_precision', 0.0)
    
    if mistakes == 0 and precision > 0:
        score += 30
        feedback.append("Precision Perfect: No active tracks were archived (30/30)")
    elif mistakes > 0:
        # Heavily penalize destroying active data
        penalty = min(30, mistakes * 5)
        earned = max(0, 30 - penalty)
        score += earned
        feedback.append(f"Precision Issue: {mistakes} active tracks were incorrectly archived. (-{penalty} pts)")
    elif precision == 0 and result.get('dead_missed_archival', 1) > 0:
        # Nothing was done?
        feedback.append("No tracks were archived at all (0/30)")

    # 3. Update Recall (30 pts)
    # Did we archive everything we should have?
    missed = result.get('dead_missed_archival', 0)
    recall = result.get('update_recall', 0.0)
    
    if recall >= 0.99:
        score += 30
        feedback.append("Recall Perfect: All dead stock flagged (30/30)")
    elif recall >= 0.90:
        score += 20
        feedback.append(f"Recall Good: {recall:.1%} of dead stock flagged (20/30)")
    elif recall >= 0.50:
        score += 10
        feedback.append(f"Recall Fair: {recall:.1%} of dead stock flagged (10/30)")
    else:
        feedback.append(f"Recall Poor: Only {recall:.1%} flagged (0/30)")

    # 4. Report (20 pts)
    if result.get('report_exists', False):
        report_score = result.get('report_score', 0)
        score += 10 # Base for existence
        score += report_score # Content quality from export script
        feedback.append(f"Report CSV created ({10 + report_score}/20)")
    else:
        feedback.append("Report CSV not found (0/20)")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }