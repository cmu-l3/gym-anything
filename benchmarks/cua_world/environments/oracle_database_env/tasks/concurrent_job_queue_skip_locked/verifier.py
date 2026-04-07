#!/usr/bin/env python3
"""
Verifier for Concurrent Job Queue task.

Scoring Criteria:
1. Procedure Exists & Valid (10 pts)
2. Functional Correctness (Single Thread) (20 pts)
   - Picks highest priority job correctly.
3. Non-Blocking Behavior (40 pts)
   - Returns immediately (< 2s) even when top rows are locked.
4. Correct "Skip" Logic (20 pts)
   - Correctly picks the next available job (Job 3) when 1 & 2 are locked.
5. State Updates (10 pts)
   - Implied by successful claim in test (verifier checks return value).

Refuses "Naive" implementation which blocks.
Refuses "Error" implementation which returns nothing on lock.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_concurrent_job_queue(traj, env_info, task_info):
    """
    Verifies that the agent implemented a non-blocking job queue.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Retrieve result files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_sql = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        copy_from_env("/tmp/procedure_source.sql", temp_sql.name)
        
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        with open(temp_sql.name, 'r', errors='ignore') as f:
            source_code = f.read().upper()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_sql.name): os.unlink(temp_sql.name)

    # Extract data
    conc_data = result_data.get("concurrency_data", {})
    procedure_exists = conc_data.get("procedure_exists", False)
    compilation_valid = conc_data.get("compilation_valid", False)
    func_passed = conc_data.get("functional_test_passed", False)
    conc_passed = conc_data.get("concurrency_test_passed", False)
    behavior = conc_data.get("behavior", "unknown")
    job_claimed = conc_data.get("job_claimed")
    exec_time = conc_data.get("execution_time", 999)

    score = 0
    feedback = []

    # 1. Compilation (10 pts)
    if procedure_exists and compilation_valid:
        score += 10
        feedback.append("Procedure CLAIM_NEXT_JOB exists and compiles.")
    else:
        return {"passed": False, "score": 0, "feedback": "Procedure does not exist or is invalid."}

    # 2. Functional Correctness (20 pts)
    if func_passed:
        score += 20
        feedback.append("Functional test passed (correctly picks highest priority).")
    else:
        feedback.append("Functional test failed. Logic for picking highest priority might be wrong.")

    # 3. Concurrency / Non-blocking (40 pts)
    if behavior == "non_blocking":
        score += 40
        feedback.append(f"Performance test passed: Returned in {exec_time:.2f}s (Non-blocking).")
    elif behavior == "blocked":
        feedback.append(f"Performance test FAILED: Procedure blocked for {exec_time:.2f}s. Likely missing 'SKIP LOCKED'.")
    else:
        feedback.append("Performance test inconclusive or error.")

    # 4. Correct 'Next' Selection (20 pts)
    # The blocker locked jobs 1 & 2. Correct behavior is to return 3.
    if job_claimed == 3:
        score += 20
        feedback.append("Skipping logic passed: Correctly claimed next available job (ID 3).")
    else:
        feedback.append(f"Skipping logic failed: Claimed Job ID {job_claimed} (Expected 3).")

    # 5. Static Analysis (10 pts)
    # Check for SKIP LOCKED in source as a sanity check
    if "SKIP LOCKED" in source_code:
        score += 10
        feedback.append("Static analysis found 'SKIP LOCKED' keyword.")
    else:
        feedback.append("Warning: 'SKIP LOCKED' keyword not found in source code.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": conc_data
    }