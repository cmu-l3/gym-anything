#!/usr/bin/env python3
"""
Verifier for Recover from Timeline task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_timeline_recovery(traj, env_info, task_info):
    """
    Verify that validate_headers function was recovered from Timeline.
    
    Checks:
    1. File exists and is readable
    2. validate_headers function is present with correct signature
    3. Function has proper docstring with Args/Returns/Raises
    4. Function body contains key validation logic (csv.DictReader, fieldnames, etc.)
    5. File has valid Python syntax
    6. Function is properly positioned (between read_csv_file and transform_row)
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace_file = "/home/ga/workspace/data_processor.py"
    
    # Create temp file for verification
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py', mode='w')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy file from container
        copy_from_env(workspace_file, temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File not found or empty at /home/ga/workspace/data_processor.py"
            }
        
        # Read file content
        content = read_file_content(temp_path)
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not read file content"
            }
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Function definition exists with correct signature
        func_pattern = r'def\s+validate_headers\s*\(\s*filepath\s*:\s*str\s*,\s*required_headers\s*:\s*List\[str\]\s*\)\s*->\s*bool\s*:'
        if re.search(func_pattern, content):
            criteria_passed += 1
            feedback_parts.append("✅ validate_headers function with correct signature found")
        else:
            # Try more lenient pattern
            func_pattern_lenient = r'def\s+validate_headers\s*\([^)]*filepath[^)]*required_headers[^)]*\)\s*->\s*bool'
            if re.search(func_pattern_lenient, content):
                criteria_passed += 0.5
                feedback_parts.append("⚠️ validate_headers function found but signature may be slightly different")
            else:
                feedback_parts.append("❌ validate_headers function with correct signature not found")
        
        # Criterion 2: Function has comprehensive docstring
        # Look for docstring with Args, Returns, Raises sections
        func_start = content.find('def validate_headers')
        if func_start != -1:
            # Extract function (approximately - up to next def or end)
            next_def = content.find('\ndef ', func_start + 1)
            if next_def == -1:
                func_content = content[func_start:]
            else:
                func_content = content[func_start:next_def]
            
            # Check for docstring
            if '"""' in func_content:
                docstring_start = func_content.find('"""')
                docstring_end = func_content.find('"""', docstring_start + 3)
                if docstring_end != -1:
                    docstring = func_content[docstring_start:docstring_end + 3]
                    
                    has_args = 'Args:' in docstring or 'Arguments:' in docstring or 'Parameters:' in docstring
                    has_returns = 'Returns:' in docstring or 'Return:' in docstring
                    has_raises = 'Raises:' in docstring or 'Raise:' in docstring
                    
                    if has_args and has_returns:
                        criteria_passed += 1
                        if has_raises:
                            feedback_parts.append("✅ Comprehensive docstring with Args, Returns, and Raises")
                        else:
                            feedback_parts.append("✅ Docstring with Args and Returns (Raises section optional)")
                    else:
                        criteria_passed += 0.3
                        feedback_parts.append("⚠️ Docstring present but missing some sections (Args/Returns/Raises)")
                else:
                    criteria_passed += 0.2
                    feedback_parts.append("⚠️ Docstring started but not properly closed")
            else:
                feedback_parts.append("❌ Function missing docstring")
        
        # Criterion 3: Function contains key validation logic
        required_elements = [
            (r'csv\.DictReader', 'csv.DictReader usage'),
            (r'fieldnames', 'fieldnames access'),
            (r'required_headers', 'required_headers parameter usage'),
        ]
        
        elements_found = 0
        missing_elements = []
        
        for pattern, description in required_elements:
            if re.search(pattern, content):
                elements_found += 1
            else:
                missing_elements.append(description)
        
        if elements_found == len(required_elements):
            criteria_passed += 1
            feedback_parts.append("✅ All key validation logic elements present")
        elif elements_found >= 2:
            criteria_passed += 0.6
            feedback_parts.append(f"⚠️ Most validation logic present, missing: {', '.join(missing_elements)}")
        else:
            feedback_parts.append(f"❌ Missing key validation logic: {', '.join(missing_elements)}")
        
        # Criterion 4: Function returns boolean values
        if func_start != -1:
            if next_def == -1:
                func_content = content[func_start:]
            else:
                func_content = content[func_start:next_def]
            
            if re.search(r'return\s+(True|False)', func_content):
                criteria_passed += 1
                feedback_parts.append("✅ Function returns boolean values")
            else:
                feedback_parts.append("❌ Function should return True or False")
        
        # Criterion 5: Verify Python syntax is valid
        try:
            compile(content, temp_path, 'exec')
            criteria_passed += 1
            feedback_parts.append("✅ Valid Python syntax")
        except SyntaxError as e:
            feedback_parts.append(f"❌ Syntax error in file: {str(e)[:50]}")
        
        # Criterion 6: Function is in correct position (between read_csv_file and transform_row)
        read_csv_pos = content.find('def read_csv_file')
        validate_pos = content.find('def validate_headers')
        transform_pos = content.find('def transform_row')
        
        if validate_pos != -1 and read_csv_pos != -1 and transform_pos != -1:
            if read_csv_pos < validate_pos < transform_pos:
                criteria_passed += 1
                feedback_parts.append("✅ Function properly positioned between read_csv_file and transform_row")
            else:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ Function exists but may not be in optimal position")
        elif validate_pos != -1:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Function exists but position could not be verified")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 90  # Need 90% to pass (5.4/6 criteria)
        
        feedback = " | ".join(feedback_parts)
        
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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception as e:
                logger.warning(f"Failed to delete temp file: {e}")
