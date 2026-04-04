#!/usr/bin/env python3
"""
Verifier for optimize_string_concatenation task.

Criteria:
1.  Code must compile (Implicit in tests passing, but we check syntax too).
2.  Must use StringBuilder or StringBuffer.
3.  Must NOT use String concatenation (+=) inside the loop.
4.  Tests must pass (Functional correctness).
"""

import json
import logging
import re
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_string_concatenation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    source_content = result.get('source_content', '')
    tests_passed = result.get('tests_passed', False)
    file_modified = result.get('file_modified', False)

    # 1. Anti-Gaming: File must be modified
    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "Task failed: Source file was not modified."}

    # 2. Check for StringBuilder usage (30 points)
    # Allow StringBuilder or StringBuffer (thread-safe, though SB is preferred)
    has_builder = 'StringBuilder' in source_content or 'StringBuffer' in source_content
    if has_builder:
        score += 30
        feedback_parts.append("StringBuilder/StringBuffer usage detected (+30)")
    else:
        feedback_parts.append("No StringBuilder or StringBuffer found")

    # 3. Check for removal of bad concatenation (30 points)
    # We look for the pattern: variable += "..." inside the file.
    # The original variable was 'result'.
    # A robust regex would look for `result \+=` or `result = result \+`
    # We assume the user might change variable names, so we look for `+=` inside the loop body.
    # Since parsing Java robustly with regex is hard, we'll check if `+=` count is 0 in the method.
    
    # Simple check: Does the file contain `+=` combined with string literals?
    # Or simply: Does it contain `+=` at all? In the refactored code, `+=` should ideally be gone
    # or replaced by `.append()`.
    
    has_plus_equals = '+=' in source_content
    
    # More specific: Check if the original bad line exists
    # Original: result += "OBX|" + ...
    original_pattern = r'\+=\s*"OBX\|"'
    
    if re.search(original_pattern, source_content):
        feedback_parts.append("Inefficient concatenation ('+=') still detected")
    elif not has_plus_equals:
        score += 30
        feedback_parts.append("String concatenation ('+=') removed (+30)")
    else:
        # += exists but maybe not for the main string?
        # Let's give partial credit if `.append` is frequent
        append_count = source_content.count('.append(')
        if append_count >= 5:
            score += 30
            feedback_parts.append("Concatenation replaced with append() (+30)")
        else:
            score += 15
            feedback_parts.append("Some concatenation remaining or low append usage (+15)")

    # 4. Functional Correctness (Tests Passed) (20 points)
    if tests_passed:
        score += 20
        feedback_parts.append("JUnit tests passed (+20)")
    else:
        feedback_parts.append("JUnit tests failed or project did not compile")

    # 5. Compilation/Validity (20 points)
    # If tests passed, it compiled. If tests failed, we can't be sure, but we assume 0 here.
    if tests_passed:
        score += 20
        feedback_parts.append("Code compiles (+20)")

    # 6. VLM Verification (Bonus/Confirmation)
    # (Optional implementation here)

    passed = score >= 80 and tests_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }