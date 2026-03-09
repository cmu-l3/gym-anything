#!/usr/bin/env python3
"""
Verifier for refactor_loops_to_streams task.

Criteria:
1. Build & Test Success (40 pts): mvn test passes with 0 failures.
2. Loops Removed (30 pts): No 'for (' loops remaining in the file.
3. Streams Used (30 pts): 'stream()', 'filter', 'map', 'collect' present.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_loops_to_streams(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    service_content = result.get('service_content', '')
    file_modified = result.get('file_modified', False)
    tests_passed = result.get('tests_passed', 0)
    tests_failed = result.get('tests_failed', 0)
    tests_errors = result.get('tests_errors', 0)
    
    if not service_content:
        return {"passed": False, "score": 0, "feedback": "AnalyticsService.java not found or empty"}

    # --- Criterion 1: Build & Tests (40 pts) ---
    # We expect at least 5 tests (from setup script)
    if tests_passed >= 5 and tests_failed == 0 and tests_errors == 0:
        score += 40
        feedback_parts.append("Tests passed (functional correctness maintained)")
    elif tests_passed > 0:
        partial = int(40 * (tests_passed / (tests_passed + tests_failed + tests_errors)))
        score += partial
        feedback_parts.append(f"Some tests failed ({tests_passed} passed, {tests_failed} failed)")
    else:
        feedback_parts.append("Tests failed or did not run")

    # --- Criterion 2: Loops Removed (30 pts) ---
    # Remove comments to avoid false positives (rudimentary regex)
    content_no_comments = re.sub(r'//.*', '', service_content)
    content_no_comments = re.sub(r'/\*[\s\S]*?\*/', '', content_no_comments)
    
    # Check for 'for (' or 'for(' loops
    # Using regex to catch 'for (' and 'for(' but try to respect boundaries
    loop_match = re.search(r'\bfor\s*\(', content_no_comments)
    while_match = re.search(r'\bwhile\s*\(', content_no_comments)
    
    if not loop_match and not while_match:
        score += 30
        feedback_parts.append("Loops successfully removed")
    else:
        feedback_parts.append("Imperative loops still detected")

    # --- Criterion 3: Streams Used (30 pts) ---
    stream_keywords = ['stream(', 'stream.', '.filter', '.map', '.collect', '.toList', 'Collectors.']
    found_keywords = [k for k in stream_keywords if k in service_content]
    
    # Needs at least 3 distinct stream-related keywords to convince us
    if len(set(found_keywords)) >= 3:
        score += 30
        feedback_parts.append(f"Stream API usage detected ({len(found_keywords)} keywords)")
    elif len(set(found_keywords)) > 0:
        score += 15
        feedback_parts.append("Partial Stream API usage detected")
    else:
        feedback_parts.append("No Stream API usage detected")

    # --- Anti-Gaming Check ---
    if not file_modified:
        score = 0
        feedback_parts = ["File was not modified"]

    passed = score >= 90  # Strict pass threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }