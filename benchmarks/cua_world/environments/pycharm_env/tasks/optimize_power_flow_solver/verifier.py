#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_power_flow_solver(traj, env_info, task_info):
    """
    Verify optimization of power flow solver.
    Criteria:
    1. Functional Correctness (30 pts): Pytest passes (physics preserved).
    2. Performance (40 pts): Total runtime < 1.0s (legacy was ~20s+).
    3. Vectorization (30 pts): Static analysis shows numpy usage and reduced loops.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Retrieve result
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

    score = 0
    feedback = []
    
    # 1. Correctness (30 pts)
    pytest_code = result.get("pytest_exit_code", 1)
    if pytest_code == 0:
        score += 30
        feedback.append("Correctness: PASS (All physics tests passed)")
    else:
        feedback.append("Correctness: FAIL (Tests failed - broken physics)")

    # 2. Performance (40 pts)
    total_time = result.get("total_time", 999.0)
    target_time = task_info.get('metadata', {}).get('target_runtime_sec', 1.0)
    
    if total_time < target_time:
        score += 40
        feedback.append(f"Performance: PASS ({total_time:.4f}s < {target_time}s)")
    elif total_time < 5.0:
        # Partial credit for some optimization
        score += 20
        feedback.append(f"Performance: PARTIAL ({total_time:.4f}s) - Faster but missed <1s target")
    else:
        feedback.append(f"Performance: FAIL ({total_time:.4f}s) - Too slow")

    # 3. Vectorization Evidence (30 pts)
    # Heuristics from static analysis
    stats = result.get("static_analysis", {})
    solver_loops = stats.get("loops_solver", 100)
    uses_matmul = stats.get("uses_matmul", 0) > 0 or stats.get("uses_numpy_sum", 0) > 0
    
    vectorized_score = 0
    if uses_matmul:
        vectorized_score += 15
        feedback.append("Vectorization: NumPy Matrix ops detected (+15)")
    
    # Legacy solver had nested loops (~3-4 levels or explicit bus iteration).
    # Optimized solver should have significantly fewer loops (just the iteration loop).
    if solver_loops < 5: 
        vectorized_score += 15
        feedback.append("Vectorization: Loops significantly reduced (+15)")
    elif solver_loops < 20:
        vectorized_score += 5
        feedback.append("Vectorization: Loops partially reduced (+5)")
    else:
        feedback.append("Vectorization: High loop count detected (Did you vectorize?)")
        
    score += vectorized_score

    # Final Check
    passed = (score >= 70) and (pytest_code == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }