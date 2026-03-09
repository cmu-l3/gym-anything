#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dynamic_test_suite(traj, env_info, task_info):
    """
    Verifies that the agent created a Test Plan and a Dynamic Query-Based Suite 
    with the correct criteria.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_suite_type = metadata.get('expected_suite_type', 'DynamicTestSuite')
    expected_count = metadata.get('expected_test_case_count', 3)
    
    # Path to result file on Windows VM
    # Note: Using forward slashes usually works with the copy util, but fallback to backslash if needed
    remote_path = "C:/Users/Docker/task_results/configure_dynamic_test_suite_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Test Plan exists (20 pts)
    if result.get('plan_found'):
        score += 20
        feedback_parts.append("Test Plan 'Nightly Regression' created")
    else:
        feedback_parts.append("Test Plan 'Nightly Regression' NOT found")
        # Early fail if parent container missing
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Test Suite exists (10 pts)
    if result.get('suite_found'):
        score += 10
        feedback_parts.append("Suite 'Auto-Regression' created")
    else:
        feedback_parts.append("Suite 'Auto-Regression' NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Suite is Dynamic (30 pts)
    # Critical - verifying it's query-based, not static
    actual_type = result.get('suite_type')
    if actual_type == expected_suite_type:
        score += 30
        feedback_parts.append("Suite is Query-based (Dynamic)")
    else:
        feedback_parts.append(f"Suite type is incorrect: {actual_type} (expected {expected_suite_type})")

    # Criterion 4: Query Logic Check (30 pts)
    # Check if query string contains key filtering terms
    query_str = str(result.get('query_string', '')).lower()
    
    # Check for Priority=1
    has_priority = ('priority' in query_str and '1' in query_str)
    # Check for Tags contains Regression
    has_tag = ('tags' in query_str and 'regression' in query_str)
    
    if has_priority and has_tag:
        score += 30
        feedback_parts.append("Query criteria correct (Priority & Tags)")
    elif has_priority or has_tag:
        score += 15
        feedback_parts.append("Query criteria partially correct (Missing Priority or Tags check)")
    else:
        feedback_parts.append("Query criteria incorrect or missing logic")

    # Criterion 5: Correct Population Count (10 pts)
    # This verifies the query actually works against real data
    actual_count = result.get('test_case_count', 0)
    if actual_count == expected_count:
        score += 10
        feedback_parts.append(f"Suite correctly populated with {actual_count} cases")
    else:
        feedback_parts.append(f"Suite population mismatch: found {actual_count}, expected {expected_count}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }