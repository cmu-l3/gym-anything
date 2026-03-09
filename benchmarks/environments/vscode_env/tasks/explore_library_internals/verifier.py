#!/usr/bin/env python3
"""
Verifier for Library Exploration task
"""

import sys
import os
import logging
import tempfile
import ast
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_library_exploration(traj, env_info, task_info):
    """
    Verify that agent explored library internals and created correct test file.
    
    Checks:
    1. Library navigation (accessed datatools source files)
    2. Test file created (test_datatools.py exists)
    3. Correct import (from datatools import process_data)
    4. Function usage (calls process_data with correct parameters)
    5. Code quality (valid Python syntax)
    6. Explanatory content (has comments)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='library_verify_')
    
    try:
        criteria_passed = 0
        feedback_parts = []
        
        # Check 1: Library Navigation
        # Try to detect if library source files were accessed
        library_accessed = False
        
        # Method 1: Check VSCode storage for recently opened files
        try:
            vscode_storage = os.path.join(temp_dir, "vscode_storage.json")
            copy_from_env("/tmp/vscode_storage.json", vscode_storage)
            
            if os.path.exists(vscode_storage) and os.path.getsize(vscode_storage) > 0:
                content = read_file_content(vscode_storage)
                if 'datatools' in content or 'site-packages' in content:
                    library_accessed = True
                    feedback_parts.append("✅ Library navigation detected (VSCode history)")
        except Exception as e:
            logger.debug(f"Could not check VSCode storage: {e}")
        
        # Method 2: Check recent files list
        if not library_accessed:
            try:
                recent_files = os.path.join(temp_dir, "recent_files.txt")
                copy_from_env("/tmp/recent_files.txt", recent_files)
                
                if os.path.exists(recent_files):
                    content = read_file_content(recent_files)
                    # If multiple Python files were accessed, likely explored library
                    lines = [l for l in content.strip().split('\n') if l]
                    if len(lines) > 2:  # More than just data_processor.py and test file
                        library_accessed = True
                        feedback_parts.append("✅ Multiple files accessed (likely explored library)")
            except Exception as e:
                logger.debug(f"Could not check recent files: {e}")
        
        # Method 3: Soft check - if test file is correct, assume library was explored
        # We'll upgrade this later if test file is good
        
        if library_accessed:
            criteria_passed += 1
        else:
            feedback_parts.append("⚠️ Library navigation not clearly detected")
        
        # Check 2: Test File Created
        test_file_path = os.path.join(temp_dir, "test_datatools.py")
        try:
            copy_from_env("/tmp/test_datatools.py", test_file_path)
        except Exception as e:
            feedback_parts.append(f"❌ Test file not found: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(test_file_path) or os.path.getsize(test_file_path) < 50:
            feedback_parts.append("❌ Test file missing or too short")
            return {
                "passed": False,
                "score": int((criteria_passed / 6) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Test file created")
        
        # Read test file content
        content = read_file_content(test_file_path)
        
        # Check 3: Correct Import
        has_correct_import = (
            'from datatools import process_data' in content or
            'from datatools.core import process_data' in content or
            ('import datatools' in content and 'datatools.process_data' in content)
        )
        
        if has_correct_import:
            criteria_passed += 1
            feedback_parts.append("✅ Correct import statement found")
        else:
            feedback_parts.append("❌ Missing or incorrect import statement")
        
        # Check 4: Function Usage
        # The correct parameters are: data, mode='default', strict=False
        # We want to see process_data called with actual correct parameters
        
        has_function_call = 'process_data(' in content
        
        # Check that they're NOT using the wrong parameter 'ignore_errors'
        uses_wrong_param = 'ignore_errors' in content
        
        # Check if using correct parameter 'strict'
        uses_strict = 'strict' in content
        
        if has_function_call and not uses_wrong_param and uses_strict:
            criteria_passed += 1
            feedback_parts.append("✅ Function used with correct parameters")
            # If they got parameters right, they must have read the source
            if not library_accessed:
                criteria_passed += 1  # Retroactively give credit for library navigation
                feedback_parts[0] = "✅ Library navigation inferred from correct usage"
        elif has_function_call and uses_wrong_param:
            feedback_parts.append("❌ Still using incorrect parameter 'ignore_errors'")
        elif has_function_call:
            feedback_parts.append("⚠️ Function called but parameters unclear")
        else:
            feedback_parts.append("❌ No function call found")
        
        # Check 5: Code Quality (valid Python syntax)
        try:
            ast.parse(content)
            criteria_passed += 1
            feedback_parts.append("✅ Valid Python syntax")
        except SyntaxError as e:
            feedback_parts.append(f"❌ Syntax error: {str(e)}")
        
        # Check 6: Explanatory Content
        has_comments = '#' in content or '"""' in content or "'''" in content
        
        if has_comments:
            criteria_passed += 1
            feedback_parts.append("✅ Contains explanatory comments")
        else:
            feedback_parts.append("⚠️ No comments explaining the solution")
        
        # Calculate score
        score = int((criteria_passed / 6) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "criteria_met": criteria_passed
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
