#!/usr/bin/env python3
"""
Verifier for optimize_patient_lookup_speed task.

Criteria:
1. Index Creation (40 pts): Index exists on fchpat.FchPat_NumSS.
2. Correct Configuration (30 pts): Index name is 'idx_numss' (or reasonable) and is active.
3. Proof File (10 pts): File exists.
4. Optimization Verification (20 pts): 'EXPLAIN' shows the index is actually used.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_patient_lookup_speed(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []
    
    # Extract data
    db_state = result.get('db_state', {})
    explain_output = result.get('explain_output', {})
    proof_exists = result.get('proof_file_exists', False)
    
    # 1. Index Creation (40 pts)
    index_count = db_state.get('index_count', 0)
    index_names = db_state.get('index_names', "") or ""
    
    if index_count > 0:
        score += 40
        feedback.append("Index found on FchPat_NumSS.")
    else:
        feedback.append("FAIL: No index found on FchPat_NumSS.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Correct Configuration (30 pts)
    # Task requested name 'idx_numss'
    expected_name = task_info.get('metadata', {}).get('expected_index_name', 'idx_numss')
    
    if expected_name.lower() in index_names.lower():
        score += 30
        feedback.append(f"Index name '{expected_name}' matches request.")
    else:
        # Partial credit if they made an index but named it wrong
        score += 10
        feedback.append(f"Index exists but name '{index_names}' does not match expected '{expected_name}'.")

    # 3. Proof File (10 pts)
    if proof_exists:
        score += 10
        feedback.append("Proof file optimization_proof.txt created.")
    else:
        feedback.append("Proof file missing.")

    # 4. Optimization Verification (20 pts)
    # Check if MySQL actually uses the index (from EXPLAIN output)
    # MySQL EXPLAIN JSON format: { "query_block": { "table": { "key": "idx_numss", ... } } }
    try:
        query_block = explain_output.get('query_block', {})
        table_info = query_block.get('table', {})
        used_key = table_info.get('key', None)
        access_type = table_info.get('access_type', '')

        if used_key and used_key != "NULL":
            score += 20
            feedback.append(f"Database engine confirms optimization: using key '{used_key}' (type: {access_type}).")
        else:
            feedback.append(f"Warning: Database engine is NOT using the index (key: {used_key}, type: {access_type}). Scan might still be full table.")
    except Exception as e:
        feedback.append(f"Could not parse EXPLAIN output: {str(e)}")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }