#!/usr/bin/env python3
"""
Verifier for create_accounting_journal task.

Checks:
1. Journal with code 'SUBV' exists in the database.
2. Journal name matches 'Subventions PAC' (case-insensitive).
3. Journal nature is 'various'.
4. Journal currency is 'EUR'.
5. Journal was created AFTER the task started (anti-gaming).
6. Total journal count increased by 1.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_accounting_journal(traj, env_info, task_info):
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

    # 2. Extract Data
    task_start = result.get('task_start_time', 0)
    initial_count = result.get('initial_journal_count', 0)
    final_count = result.get('final_journal_count', 0)
    journal_found = result.get('journal_found', False)
    journal_data = result.get('journal_data', {})
    
    j_name = journal_data.get('name', '')
    j_nature = journal_data.get('nature', '')
    j_currency = journal_data.get('currency', '')
    j_created_at = journal_data.get('created_at', 0)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Metadata expectations
    expected_name = task_info.get('metadata', {}).get('expected_name', 'Subventions PAC')
    expected_nature = task_info.get('metadata', {}).get('expected_nature', 'various')
    expected_currency = task_info.get('metadata', {}).get('expected_currency', 'EUR')

    # Criterion 1: Journal exists (20 pts)
    if journal_found:
        score += 20
        feedback_parts.append("Journal with code 'SUBV' found (+20)")
    else:
        feedback_parts.append("Journal with code 'SUBV' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Correct Name (20 pts)
    if expected_name.lower() in j_name.lower():
        score += 20
        feedback_parts.append(f"Name correct ('{j_name}') (+20)")
    else:
        feedback_parts.append(f"Name incorrect. Expected '{expected_name}', got '{j_name}'")

    # Criterion 3: Correct Nature (20 pts)
    # The UI might select 'various', 'diverse', or 'operations'. DB usually stores 'various'.
    if j_nature == expected_nature:
        score += 20
        feedback_parts.append(f"Nature correct ('{j_nature}') (+20)")
    else:
        feedback_parts.append(f"Nature incorrect. Expected '{expected_nature}', got '{j_nature}'")

    # Criterion 4: Correct Currency (10 pts)
    if j_currency == expected_currency:
        score += 10
        feedback_parts.append(f"Currency correct ('{j_currency}') (+10)")
    else:
        feedback_parts.append(f"Currency incorrect. Expected '{expected_currency}', got '{j_currency}'")

    # Criterion 5: Created During Task (15 pts)
    if j_created_at > task_start:
        score += 15
        feedback_parts.append("Created during task session (+15)")
    else:
        feedback_parts.append(f"Creation time check failed (Created: {j_created_at}, Start: {task_start})")

    # Criterion 6: Count Increase (15 pts)
    delta = final_count - initial_count
    if delta == 1:
        score += 15
        feedback_parts.append("Journal count increased by exactly 1 (+15)")
    elif delta > 0:
        score += 10
        feedback_parts.append(f"Journal count increased by {delta} (expected 1) (+10)")
    else:
        feedback_parts.append("Journal count did not increase")

    # Final Pass Determination
    # Pass if journal exists, name is roughly correct, and created during task
    passed = (score >= 60) and journal_found and (j_created_at > task_start)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }