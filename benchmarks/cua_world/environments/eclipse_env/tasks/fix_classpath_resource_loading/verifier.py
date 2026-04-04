#!/usr/bin/env python3
"""Verifier for fix_classpath_resource_loading task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_classpath_resource_loading(traj, env_info, task_info):
    """Verify that resource loading was refactored to use classpath.

    Criteria:
    1. Tests passed (30 pts)
    2. Dynamic verification passed (source file hidden) (30 pts)
    3. Source code contains 'getResource' or 'getResourceAsStream' (20 pts)
    4. Source code does NOT contain 'src/main/resources' or 'File(' (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Get result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # --- Criterion 1: Tests passed (30 points) ---
    test_exit_code = result.get("test_exit_code", -1)
    if test_exit_code == 0:
        score += 30
        feedback_parts.append("JUnit tests passed")
    else:
        feedback_parts.append("JUnit tests failed")

    # --- Criterion 2: Dynamic Verification (30 points) ---
    # This is critical anti-gaming. If they just hardcoded "src/..." absolute path, 
    # the test might pass in Eclipse but fail this check where the source file is moved.
    if result.get("dynamic_check_passed", False):
        score += 30
        feedback_parts.append("Dynamic check passed (code works portably)")
    else:
        feedback_parts.append("Dynamic check failed (code likely depends on specific file path)")

    # --- Criterion 3: Static Analysis - Positive (20 points) ---
    java_content = result.get("java_content", "")
    if "getResource" in java_content or "getResourceAsStream" in java_content:
        score += 20
        feedback_parts.append("Used getResource/getResourceAsStream")
    else:
        feedback_parts.append("Did not find getResource/getResourceAsStream usage")

    # --- Criterion 4: Static Analysis - Negative (20 points) ---
    # Check for forbidden patterns
    forbidden_patterns = []
    if "src/main/resources" in java_content:
        forbidden_patterns.append("Hardcoded 'src/main/resources'")
    if "new File(" in java_content and not "getFile()" in java_content: 
        # "new File(" matches the constructor. 
        # Note: new File(uri) is okay if obtained via getResource, but usually 
        # for this task we want getResourceAsStream directly.
        # Let's be lenient if they do new File(url.toURI()), but strict on string paths.
        # Stricter check:
        if re.search(r'new\s+File\s*\(\s*"', java_content):
            forbidden_patterns.append("Hardcoded string path in File constructor")

    if not forbidden_patterns:
        score += 20
        feedback_parts.append("No hardcoded paths detected")
    else:
        feedback_parts.append(f"Forbidden patterns found: {', '.join(forbidden_patterns)}")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }