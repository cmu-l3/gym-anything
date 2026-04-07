#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_transcript_service(traj, env_info, task_info):
    """
    Verify the optimization of the student transcript service.
    
    Criteria:
    1. Functional Correctness (40 pts): `test_transcript_correctness` passed.
    2. Performance Optimization (40 pts): `test_query_count` passed (Queries < 10).
    3. Code Quality (20 pts): Uses recognized SQLAlchemy optimization patterns (joinedload/selectinload/joins).
    
    Anti-Gaming:
    - Tests are run by the export script, so agent cannot fake test output easily.
    - We check the source code for legitimate optimization patterns.
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
    
    # 1. Functional Correctness (40 pts)
    if result.get("correctness_passed", False):
        score += 40
        feedback_parts.append("Functional correctness tests passed (40/40)")
    else:
        feedback_parts.append("Functional correctness tests FAILED (0/40)")

    # 2. Performance (40 pts)
    query_count = result.get("query_count", 999)
    try:
        query_count = int(query_count)
    except:
        query_count = 999
        
    if result.get("performance_passed", False) and query_count < 10:
        score += 40
        feedback_parts.append(f"Performance optimization passed: {query_count} queries (40/40)")
    else:
        feedback_parts.append(f"Performance optimization FAILED: {query_count} queries (Limit: <10) (0/40)")

    # 3. Code Quality / Implementation Check (20 pts)
    used_eager = result.get("used_eager_loading", False)
    used_joins = result.get("used_joins", False)
    
    if used_eager or used_joins:
        score += 20
        feedback_parts.append("Valid optimization pattern detected (eager load/join) (20/20)")
    else:
        # Check if they achieved low query count without standard patterns (unlikely but possible via raw sql or weird caching)
        if query_count < 10:
             # If they verified low queries but regex failed, manual review needed, but give points to be fair to valid unconventional approaches
             score += 20
             feedback_parts.append("Low query count achieved (Implementation pattern unrecognized but effective) (20/20)")
        else:
             feedback_parts.append("No optimization pattern detected (0/20)")

    # Final result
    passed = score >= 80
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "query_count": query_count,
            "pytest_output": result.get("pytest_output", "")[:500] + "..." # Truncate for log
        }
    }