#!/usr/bin/env python3
import json
import os
import tempfile

def verify_optimize_inventory_queries(traj, env_info, task_info):
    """
    Verify the inventory optimization task.
    
    Criteria:
    1. Functional Correctness (40 pts): test_functional.py passes.
    2. Performance Optimization (60 pts): test_performance.py passes (queries <= 10).
    3. Anti-gaming: File must be modified during the task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if file was modified (Anti-gaming)
    if not result.get('file_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No changes detected in inventory/report.py. You must modify the code to optimize it."
        }

    # 2. Functional Correctness
    if result.get('functional_tests_passed', False):
        score += 40
        feedback_parts.append("Functional tests passed (Data is correct).")
    else:
        feedback_parts.append("Functional tests failed. The report output format or data values have changed.")

    # 3. Performance Optimization
    query_count = result.get('query_count', 9999)
    try:
        query_count = int(query_count)
    except:
        query_count = 9999
        
    target_count = 10
    
    if query_count <= target_count:
        score += 60
        feedback_parts.append(f"Performance goal met: {query_count} queries (Target <= {target_count}).")
    elif query_count < 100:
        # Partial credit if they significantly improved but missed the aggregation part
        # e.g., fixed N+1 relations but still querying movements in loop? 
        # Actually, N+1 relations fix alone gets it down to ~500 queries.
        # N+1 relations + N+1 movements = 1000+
        # So < 100 implies mostly fixed.
        score += 30
        feedback_parts.append(f"Performance improved but not optimal: {query_count} queries (Target <= {target_count}).")
    else:
        feedback_parts.append(f"Performance optimization failed: {query_count} queries (Target <= {target_count}).")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }