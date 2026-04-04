#!/usr/bin/env python3
"""
Verifier for VSCode Crash Recovery task

Checks that unsaved work was recovered via Hot Exit and saved successfully.
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_whitespace(text):
    """Normalize whitespace for comparison"""
    # Remove trailing whitespace from each line
    lines = [line.rstrip() for line in text.split('\n')]
    # Remove empty lines at start and end
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return '\n'.join(lines)


def contains_function(content, function_name):
    """Check if content contains a function definition"""
    pattern = rf'def\s+{re.escape(function_name)}\s*\('
    return bool(re.search(pattern, content))


def verify_crash_recovery(traj, env_info, task_info):
    """
    Verify that VSCode Hot Exit recovered unsaved work after crash.
    
    Checks:
    1. routes.py contains new get_data() function
    2. validation.py contains new validate_email() function  
    3. test_validation.py contains new test_email_validation() method
    4. Files were saved (recovered changes persisted)
    
    Pass threshold: 3/4 criteria (75%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='crash_recovery_verify_')
    
    try:
        # Copy the actual recovered files
        routes_actual = os.path.join(temp_dir, "routes_actual.py")
        validation_actual = os.path.join(temp_dir, "validation_actual.py")
        test_actual = os.path.join(temp_dir, "test_actual.py")
        
        # Copy expected files for comparison
        routes_expected = os.path.join(temp_dir, "routes_expected.py")
        validation_expected = os.path.join(temp_dir, "validation_expected.py")
        test_expected = os.path.join(temp_dir, "test_expected.py")
        
        try:
            copy_from_env("/tmp/crash_recovery_result/routes_actual.py", routes_actual)
            copy_from_env("/tmp/crash_recovery_result/validation_actual.py", validation_actual)
            copy_from_env("/tmp/crash_recovery_result/test_actual.py", test_actual)
            
            copy_from_env("/tmp/expected_crash_recovery/routes_expected.py", routes_expected)
            copy_from_env("/tmp/expected_crash_recovery/validation_expected.py", validation_expected)
            copy_from_env("/tmp/expected_crash_recovery/test_expected.py", test_expected)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to copy files for verification: {str(e)}"
            }
        
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: routes.py has get_data function
        if os.path.exists(routes_actual) and os.path.getsize(routes_actual) > 0:
            routes_content = read_file_content(routes_actual)
            
            if contains_function(routes_content, "get_data"):
                criteria_passed += 1
                feedback_parts.append("✅ routes.py: get_data() function found")
            else:
                feedback_parts.append("❌ routes.py: get_data() function missing")
                # Show snippet of what we got
                snippet = routes_content[:200] if routes_content else "(empty)"
                feedback_parts.append(f"   Got: {snippet}...")
        else:
            feedback_parts.append("❌ routes.py: File not found or empty")
        
        # Criterion 2: validation.py has validate_email function
        if os.path.exists(validation_actual) and os.path.getsize(validation_actual) > 0:
            validation_content = read_file_content(validation_actual)
            
            if contains_function(validation_content, "validate_email"):
                criteria_passed += 1
                feedback_parts.append("✅ validation.py: validate_email() function found")
            else:
                feedback_parts.append("❌ validation.py: validate_email() function missing")
        else:
            feedback_parts.append("❌ validation.py: File not found or empty")
        
        # Criterion 3: test_validation.py has test_email_validation method
        if os.path.exists(test_actual) and os.path.getsize(test_actual) > 0:
            test_content = read_file_content(test_actual)
            
            if contains_function(test_content, "test_email_validation"):
                criteria_passed += 1
                feedback_parts.append("✅ test_validation.py: test_email_validation() method found")
            else:
                feedback_parts.append("❌ test_validation.py: test_email_validation() method missing")
        else:
            feedback_parts.append("❌ test_validation.py: File not found or empty")
        
        # Criterion 4: Check if content matches expected (more lenient check)
        # Just verify the key functions are present with correct patterns
        routes_valid = False
        if os.path.exists(routes_actual):
            routes_content = read_file_content(routes_actual)
            # Check for both function definition and return statement
            if ('def get_data' in routes_content and 
                'return jsonify' in routes_content and 
                'data' in routes_content):
                routes_valid = True
        
        validation_valid = False
        if os.path.exists(validation_actual):
            validation_content = read_file_content(validation_actual)
            # Check for email validation with regex
            if ('def validate_email' in validation_content and 
                'pattern' in validation_content and
                're.match' in validation_content):
                validation_valid = True
        
        test_valid = False
        if os.path.exists(test_actual):
            test_content = read_file_content(test_actual)
            # Check for test method
            if ('def test_email_validation' in test_content and
                'validate_email' in test_content):
                test_valid = True
        
        if routes_valid and validation_valid and test_valid:
            criteria_passed += 1
            feedback_parts.append("✅ All files have correct implementation details")
        else:
            missing = []
            if not routes_valid:
                missing.append("routes.py")
            if not validation_valid:
                missing.append("validation.py")
            if not test_valid:
                missing.append("test_validation.py")
            feedback_parts.append(f"❌ Implementation details incomplete in: {', '.join(missing)}")
        
        # Calculate score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75  # Need 3/4 criteria
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        if passed:
            summary = f"Hot Exit recovery successful! {criteria_passed}/4 criteria met."
        else:
            summary = f"Recovery incomplete: {criteria_passed}/4 criteria met (need 3/4)."
        
        feedback = summary + " | " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
