#!/usr/bin/env python3
"""
Verifier for analyze_test_failures task
Checks that the summary correctly identifies failed tests and categorizes them
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Set

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that test failures were correctly identified and summarized
    
    Returns:
        (success, score, feedback, metadata)
    """
    
    # Expected failures (ground truth) - exact test names
    EXPECTED_FAILURES = {
        'test_database.py::test_connection_timeout': 'TimeoutError',
        'test_auth.py::test_invalid_token': 'AssertionError',
        'test_api.py::test_user_creation': 'DatabaseError',
        'test_cache.py::test_redis_unavailable': 'ConnectionError',
        'test_payments.py::test_stripe_webhook': 'AssertionError',
        'test_email.py::test_send_notification': 'TimeoutError',
        'test_auth.py::test_password_reset': 'AssertionError',
        'test_database.py::test_migration_rollback': 'IntegrityError',
        'test_api.py::test_rate_limiting': 'AssertionError',
        'test_cache.py::test_cache_invalidation': 'AssertionError',
        'test_payments.py::test_refund_processing': 'APIError',
        'test_monitoring.py::test_alert_threshold': 'AssertionError'
    }
    
    # False positives that should NOT appear as failures
    FALSE_POSITIVE_PATTERNS = [
        'test_ERROR_constant',
        'ERROR message',
        'ERROR_CODE',
        'error handling'
    ]
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available",
            "metadata": {}
        }
    
    # Copy summary file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env('/tmp/test_failures_summary.txt', temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy summary file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to copy summary file: {e}",
            "metadata": {}
        }
    
    # Check if file exists and has content
    if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
        os.unlink(temp_file.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "Summary file not found or empty. Create a file at /home/ga/workspace/test_failures_summary.txt",
            "metadata": {}
        }
    
    # Read summary content
    try:
        with open(temp_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            summary_content = f.read()
    except Exception as e:
        os.unlink(temp_file.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read summary: {e}",
            "metadata": {}
        }
    finally:
        os.unlink(temp_file.name)
    
    # Check file length (should be concise)
    summary_lines = summary_content.strip().split('\n')
    line_count = len([l for l in summary_lines if l.strip()])  # Non-empty lines
    
    if line_count > 150:
        return {
            "passed": False,
            "score": 0.2,
            "feedback": f"Summary too verbose ({line_count} non-empty lines). Should be concise (<100 lines)",
            "metadata": {'lines': line_count}
        }
    
    if line_count < 8:
        return {
            "passed": False,
            "score": 0.1,
            "feedback": f"Summary too short ({line_count} lines). Did you find the failures?",
            "metadata": {'lines': line_count}
        }
    
    # Check for false positives
    summary_lower = summary_content.lower()
    found_false_positives = []
    
    for fp in FALSE_POSITIVE_PATTERNS:
        # Check if the false positive appears in a way that suggests it's listed as a failure
        if fp.lower() in summary_lower:
            # Look for context - if it's near "FAILED" or "test_", it's likely a false positive
            fp_pattern = re.compile(r'(?:failed|test_.*?).*?' + re.escape(fp.lower()), re.IGNORECASE)
            if fp_pattern.search(summary_lower):
                found_false_positives.append(fp)
    
    # Count how many expected failures were found
    found_tests: Set[str] = set()
    found_with_error_type: Set[str] = set()
    
    for test_name, error_type in EXPECTED_FAILURES.items():
        # Check if test name appears in summary (be flexible with formatting)
        # Look for the core parts: file name and test function name
        test_parts = test_name.split('::')
        if len(test_parts) == 2:
            test_file = test_parts[0]
            test_func = test_parts[1]
            
            # Check if both parts appear (allows for slight formatting differences)
            if test_file in summary_content and test_func in summary_content:
                # Verify they're close together (within 100 chars)
                file_pos = summary_content.find(test_file)
                func_pos = summary_content.find(test_func, max(0, file_pos - 50))
                
                if abs(file_pos - func_pos) < 100:
                    found_tests.add(test_name)
                    
                    # Check if error type is mentioned nearby
                    test_pos = min(file_pos, func_pos)
                    context_start = max(0, test_pos - 150)
                    context_end = min(len(summary_content), test_pos + 200)
                    context = summary_content[context_start:context_end]
                    
                    if error_type in context:
                        found_with_error_type.add(test_name)
    
    # Calculate scores
    found_count = len(found_tests)
    categorized_count = len(found_with_error_type)
    total_expected = len(EXPECTED_FAILURES)
    
    # Scoring rubric
    completeness_score = found_count / total_expected  # 0-1
    categorization_score = categorized_count / total_expected  # 0-1
    
    # Check for basic organization (headings, grouping, etc.)
    has_organization = False
    org_indicators = [
        'AssertionError', 'TimeoutError', 'ConnectionError', 
        'Error', 'Failed Tests', 'Summary', 'Category',
        '---', '###', '##', '='
    ]
    org_count = sum(1 for indicator in org_indicators if indicator in summary_content)
    if org_count >= 3:  # At least 3 organizational elements
        has_organization = True
    
    organization_score = 1.0 if has_organization else 0.5
    
    # Penalize false positives heavily
    false_positive_penalty = len(found_false_positives) * 0.15
    
    # Final score (weighted average)
    final_score = max(0, (
        completeness_score * 0.50 +      # 50% weight: finding all failures
        categorization_score * 0.25 +     # 25% weight: categorizing errors
        organization_score * 0.25         # 25% weight: being organized
    ) - false_positive_penalty)
    
    # Determine success threshold
    passed = final_score >= 0.75 and found_count >= 9  # At least 9/12 tests found
    
    # Generate detailed feedback
    feedback_parts = []
    
    feedback_parts.append(f"Found {found_count}/{total_expected} failed tests")
    
    if found_count < total_expected:
        missing_tests = set(EXPECTED_FAILURES.keys()) - found_tests
        missing_count = len(missing_tests)
        if missing_count <= 3:
            feedback_parts.append(f"Missing: {', '.join(list(missing_tests)[:3])}")
        else:
            feedback_parts.append(f"Missing {missing_count} tests")
    
    if categorized_count >= total_expected * 0.75:
        feedback_parts.append(f"Good categorization ({categorized_count}/{total_expected} with error types)")
    elif categorized_count > 0:
        feedback_parts.append(f"Partial categorization ({categorized_count}/{total_expected})")
    else:
        feedback_parts.append("Missing error type categorization")
    
    if has_organization:
        feedback_parts.append("Well-organized ✓")
    else:
        feedback_parts.append("Could be better organized")
    
    if found_false_positives:
        feedback_parts.append(f"⚠ False positives: {', '.join(found_false_positives[:2])}")
    
    if line_count > 100:
        feedback_parts.append(f"⚠ Summary verbose ({line_count} lines)")
    
    feedback = " | ".join(feedback_parts)
    
    metadata = {
        'found_tests': found_count,
        'total_expected': total_expected,
        'categorized': categorized_count,
        'organized': has_organization,
        'completeness': round(completeness_score, 2),
        'categorization': round(categorization_score, 2),
        'file_lines': line_count,
        'false_positives': len(found_false_positives)
    }
    
    # Convert score to 0-100 range
    score = int(final_score * 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "metadata": metadata
    }
