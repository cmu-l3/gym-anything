#!/usr/bin/env python3
"""Verifier for compare_and_merge_files task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_and_merge(traj, env_info, task_info):
    """
    Verify the merged DataProcessor.java file.
    
    Criteria:
    1. File exists and compiles (20 pts)
    2. Correct Package and Class Name (10 pts)
    3. Method Provenance Checks (40 pts) - did they pick the right version?
    4. Unit Tests Pass (20 pts) - functional correctness
    5. VLM / Compare Editor Usage (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
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
    
    # 1. File Existence and Compilation (20 pts)
    if result.get('file_exists') and result.get('compile_success'):
        score += 20
        feedback_parts.append("File compiles successfully")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append(f"File exists but compile failed: {result.get('compile_message')}")
    else:
        return {"passed": False, "score": 0, "feedback": "DataProcessor.java not created"}

    content = result.get('file_content', '')
    
    # 2. Package and Class Name (10 pts)
    if 'package com.acme.util;' in content:
        score += 5
    else:
        feedback_parts.append("Wrong package declaration")
        
    if 'public class DataProcessor' in content and 'class DataProcessor_v' not in content:
        score += 5
    else:
        feedback_parts.append("Wrong class name (should be DataProcessor)")

    # 3. Method Provenance (40 pts)
    # Check specific patterns that distinguish v1 from v2
    patterns = task_info.get('metadata', {}).get('verification_patterns', {})
    
    provenance_score = 0
    
    # parseCSVLine should be v1 (null check pattern)
    if re.search(patterns.get('parseCSVLine', r'if\s*\(line\s*==\s*null\)'), content):
        provenance_score += 8
    else:
        feedback_parts.append("parseCSVLine: Wrong version or missing (expected v1)")

    # computeStatistics should be v2 (parallel stream)
    if re.search(patterns.get('computeStatistics', r'\.parallelStream\(\)'), content):
        provenance_score += 8
    else:
        feedback_parts.append("computeStatistics: Wrong version or missing (expected v2)")

    # normalizeWhitespace should be v1 (unicode regex)
    if re.search(patterns.get('normalizeWhitespace', r'\\p{Zs}'), content):
        provenance_score += 8
    else:
        feedback_parts.append("normalizeWhitespace: Wrong version or missing (expected v1)")
        
    # sanitizeHTML should exist (v1)
    if 'sanitizeHTML' in content and 'HTML_TAGS' in content:
        provenance_score += 8
    else:
        feedback_parts.append("sanitizeHTML: Missing")

    # transformToMap should exist (v2)
    if 'transformToMap' in content:
        provenance_score += 4
    else:
        feedback_parts.append("transformToMap: Missing")

    # validateEmail should exist (v2)
    if 'validateEmail' in content:
        provenance_score += 4
    else:
        feedback_parts.append("validateEmail: Missing")
        
    score += provenance_score
    
    # 4. Unit Tests (20 pts)
    tests_passed = result.get('tests_passed', 0)
    tests_total = result.get('tests_run', 0)
    
    if tests_total > 0:
        pass_ratio = tests_passed / tests_total
        test_points = int(20 * pass_ratio)
        score += test_points
        feedback_parts.append(f"Tests: {tests_passed}/{tests_total} passed")
    else:
        feedback_parts.append("No tests ran")

    # 5. VLM / Anti-Gaming (10 pts)
    # Check if they actually used the Compare Editor?
    # Hard to check programmatically, but we can verify file creation time is valid
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File timestamp suspicious (pre-dates task?)")

    passed = score >= 60 and result.get('compile_success')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }