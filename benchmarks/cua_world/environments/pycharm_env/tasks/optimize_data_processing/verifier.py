#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_optimize_data_processing(traj, env_info, task_info):
    """
    Verify the optimize_data_processing task.
    
    Scoring (100 pts total):
    - 20 pts: Dedup optimized (Perf test pass + Code uses set)
    - 20 pts: Aggregate optimized (Perf test pass + Code uses dict)
    - 20 pts: TopK optimized (Perf test pass + Code uses efficient sort/heap)
    - 20 pts: Join optimized (Perf test pass + Code uses hash/dict)
    - 20 pts: No regressions (All correctness tests pass)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/optimize_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Check correctness (No regressions)
    if result.get('correctness_passed'):
        score += 20
        feedback.append("Correctness tests passed (+20)")
    else:
        feedback.append("Correctness tests FAILED (0 pts for regression)")

    # Parse performance test output to see individual passes
    perf_out = result.get('test_output', {}).get('performance', '')
    
    # Helper to check individual test pass
    def check_perf_pass(test_name):
        # Look for "test_name PASSED" or dot indicator if verbose is off
        # The export script uses -v so we expect "test_perf_dedup PASSED"
        return f"{test_name} PASSED" in perf_out

    # Helper to analyze source
    source_analysis = result.get('source_analysis', {})

    # 1. Deduplication
    if check_perf_pass('test_perf_dedup') and source_analysis.get('dedup_uses_set'):
        score += 20
        feedback.append("Dedup optimized (+20)")
    elif check_perf_pass('test_perf_dedup'):
        score += 10
        feedback.append("Dedup perf passed but implementation unclear (+10)")
    else:
        feedback.append("Dedup too slow")

    # 2. Aggregation
    if check_perf_pass('test_perf_aggregate') and source_analysis.get('agg_uses_dict'):
        score += 20
        feedback.append("Aggregate optimized (+20)")
    elif check_perf_pass('test_perf_aggregate'):
        score += 10
        feedback.append("Aggregate perf passed but implementation unclear (+10)")
    else:
        feedback.append("Aggregate too slow")

    # 3. TopK
    if check_perf_pass('test_perf_topk') and source_analysis.get('topk_uses_fast_sort'):
        score += 20
        feedback.append("TopK optimized (+20)")
    elif check_perf_pass('test_perf_topk'):
        score += 10
        feedback.append("TopK perf passed but implementation unclear (+10)")
    else:
        feedback.append("TopK too slow")

    # 4. Join
    if check_perf_pass('test_perf_join') and source_analysis.get('join_uses_hash'):
        score += 20
        feedback.append("Join optimized (+20)")
    elif check_perf_pass('test_perf_join'):
        score += 10
        feedback.append("Join perf passed but implementation unclear (+10)")
    else:
        feedback.append("Join too slow")

    return {
        "passed": score >= 60 and result.get('correctness_passed'),
        "score": score,
        "feedback": ", ".join(feedback)
    }