#!/usr/bin/env python3
"""
Verifier for migrate_weather_lib task.
Checks if tests pass and if code was modernized.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_weather_lib(traj, env_info, task_info):
    """
    Verify Python 2 to 3 migration.
    
    Scoring Breakdown (100 pts):
    - 60 pts: Test results (5 pts per passed test, max 12 tests)
    - 25 pts: Source Code Quality (Absence of Py2 artifacts & presence of Py3 idioms)
    - 15 pts: 'Do Nothing' check (Files must be modified)
    
    Pass Threshold: 60/100
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Test Results (Max 60 pts)
    # 12 tests total. 5 pts each.
    tests_passed = result.get('tests_passed', 0)
    total_tests = result.get('total_tests', 0)
    
    test_score = tests_passed * 5
    if test_score > 60: test_score = 60 # Cap just in case
    
    score += test_score
    feedback_parts.append(f"Tests passed: {tests_passed}/{total_tests} (+{test_score} pts)")

    if result.get('tests_error', 0) > 0:
        feedback_parts.append(f"Warning: {result['tests_error']} tests failed with errors (likely SyntaxErrors)")

    # 2. Source Code Quality (Max 25 pts)
    # Check for remaining artifacts
    artifacts_found = result.get('artifacts_found', False)
    if not artifacts_found:
        score += 10
        feedback_parts.append("No Python 2 artifacts found (+10 pts)")
    else:
        feedback_parts.append(f"Python 2 artifacts remaining: {result.get('artifact_details', 'Unknown')}")

    # Check for specific fixes
    fixes = result.get('specific_fixes', {})
    fix_count = sum(1 for v in fixes.values() if v)
    # 5 checks, 3 pts each
    fix_score = fix_count * 3
    score += fix_score
    feedback_parts.append(f"Verified {fix_count}/5 specific Python 3 idioms (+{fix_score} pts)")

    # 3. Anti-Gaming (Max 15 pts)
    files_modified = result.get('files_modified', False)
    if files_modified:
        score += 15
        feedback_parts.append("Files were modified during task (+15 pts)")
    else:
        feedback_parts.append("Files were NOT modified significantly (0 pts)")
        # Critical failure if no files modified but tests pass (impossible unless pre-solved)
        if tests_passed == 12:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Suspicious activity: Tests passed but source files not modified."
            }

    # Pass logic
    passed = score >= 60 and tests_passed >= 8  # Require majority of tests to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }