#!/usr/bin/env python3
"""
Verifier for Write Bug Reproduction Test task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bug_test(traj, env_info, task_info):
    """
    Verify that bug reproduction test was written correctly.
    
    Checks:
    1. Test file was modified (contains new test function)
    2. New test function exists with appropriate name
    3. Test calls normalize_whitespace with empty/whitespace-only input
    4. Test includes documentation about the bug
    5. (Bonus) Test was executed with pytest
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    test_file_path = "/home/ga/workspace/data-processor/tests/test_text_utils.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    
    try:
        # Copy test file
        copy_from_env(test_file_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Test file not found or empty"}
        
        content = read_file_content(temp_file.name)
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Check for new test function with appropriate name
        # Look for patterns like: test_normalize_empty, test_empty_string, test_bug, etc.
        test_function_patterns = [
            r'def\s+test_\w*empty\w*\s*\(',
            r'def\s+test_\w*bug\w*\s*\(',
            r'def\s+test_\w*edge\w*\s*\(',
            r'def\s+test_\w*whitespace\w*edge\w*\s*\(',
            r'def\s+test_normalize_\w*empty\w*\s*\(',
        ]
        
        has_test_function = False
        test_function_name = None
        for pattern in test_function_patterns:
            match = re.search(pattern, content, re.IGNORECASE)
            if match:
                has_test_function = True
                # Extract function name
                func_match = re.search(r'def\s+(\w+)\s*\(', match.group(0))
                if func_match:
                    test_function_name = func_match.group(1)
                break
        
        if has_test_function:
            criteria_passed += 1
            feedback_parts.append(f"✅ New test function found: {test_function_name or 'test_*'}")
        else:
            feedback_parts.append("❌ No test function found for empty string edge case (expected name like 'test_normalize_empty_string_bug')")
        
        # Criterion 2: Verify test calls normalize_whitespace with empty/whitespace-only input
        # Look for patterns like: normalize_whitespace(""), normalize_whitespace("   "), normalize_whitespace(' ')
        test_calls_patterns = [
            r'normalize_whitespace\s*\(\s*["\']["\']',  # normalize_whitespace("")
            r'normalize_whitespace\s*\(\s*["\'][\s]+["\']',  # normalize_whitespace("   ")
            r'normalize_whitespace\s*\(\s*["\'][\s]*["\']',  # normalize_whitespace(" ")
        ]
        
        has_empty_test_call = False
        for pattern in test_calls_patterns:
            if re.search(pattern, content):
                has_empty_test_call = True
                break
        
        # Also check for empty string literals in single quotes
        if not has_empty_test_call:
            if re.search(r"normalize_whitespace\s*\(\s*'\s*'\s*\)", content):
                has_empty_test_call = True
        
        if has_empty_test_call:
            criteria_passed += 1
            feedback_parts.append("✅ Test calls normalize_whitespace with empty/whitespace-only input")
        else:
            feedback_parts.append("❌ Test doesn't call normalize_whitespace with empty/whitespace input (expected: normalize_whitespace('') or normalize_whitespace('   '))")
        
        # Criterion 3: Check for documentation about the bug
        # Look for: docstring, comments mentioning bug/edge case/#4729/empty string
        bug_keywords = [
            '#4729',
            'bug #4729',
            'Bug #4729',
            'empty string',
            'edge case',
            'IndexError',
            'crashes',
            'fails',
        ]
        
        has_documentation = False
        doc_type = None
        
        # Check in docstrings (triple quotes after function def)
        docstring_pattern = r'def\s+test_\w+\s*\([^)]*\)\s*:\s*["\'"]{3}([^"\']+)["\'"]{3}'
        docstring_match = re.search(docstring_pattern, content, re.DOTALL)
        if docstring_match:
            docstring_content = docstring_match.group(1).lower()
            for keyword in bug_keywords:
                if keyword.lower() in docstring_content:
                    has_documentation = True
                    doc_type = "docstring"
                    break
        
        # Check in comments
        if not has_documentation:
            comment_lines = [line for line in content.split('\n') if '#' in line]
            for line in comment_lines:
                line_lower = line.lower()
                for keyword in bug_keywords:
                    if keyword.lower() in line_lower:
                        has_documentation = True
                        doc_type = "comment"
                        break
                if has_documentation:
                    break
        
        if has_documentation:
            criteria_passed += 1
            feedback_parts.append(f"✅ Test includes documentation ({doc_type}) about the bug")
        else:
            feedback_parts.append("❌ Test lacks documentation about what bug it's testing (expected docstring or comment mentioning Bug #4729 or edge case)")
        
        # Criterion 4 (Bonus): Check if test was executed
        # Check bash history for pytest execution
        bash_history_path = "/home/ga/.bash_history"
        bash_history_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        
        test_was_executed = False
        try:
            copy_from_env(bash_history_path, bash_history_temp.name)
            if os.path.exists(bash_history_temp.name) and os.path.getsize(bash_history_temp.name) > 0:
                history_content = read_file_content(bash_history_temp.name)
                
                # Look for pytest execution
                if 'pytest' in history_content and 'test_text_utils' in history_content:
                    test_was_executed = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Test was executed with pytest")
                else:
                    feedback_parts.append("⚠️ Test was not executed with pytest (optional but recommended)")
            else:
                feedback_parts.append("⚠️ Could not verify if test was executed")
        except Exception as e:
            logger.warning(f"Could not check bash history: {e}")
            feedback_parts.append("⚠️ Could not verify test execution")
        finally:
            if os.path.exists(bash_history_temp.name):
                os.unlink(bash_history_temp.name)
        
        # Calculate score
        # First 3 criteria are mandatory, 4th is bonus
        # Pass threshold: 3/4 criteria (75%)
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed >= 3
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
