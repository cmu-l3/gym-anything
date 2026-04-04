#!/usr/bin/env python3
"""
Verifier for Modernize Callback Pattern task
"""

import sys
import os
import logging
import tempfile
import re
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_modernize_callback(traj, env_info, task_info):
    """
    Verify that callback-to-Promise/async-await migration was completed correctly.
    
    Checks:
    1. No callback patterns remain in main file
    2. Async/await patterns present in main file
    3. Error handling preserved (try/catch or .catch())
    4. Test file updated to use async/await
    5. Code is syntactically valid
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='callback_verify_')
    
    try:
        # Copy files from container
        main_file_container = "/home/ga/workspace/callback_migration/file_processor.js"
        test_file_container = "/home/ga/workspace/callback_migration/test/file_processor.test.js"
        syntax_check_container = "/tmp/syntax_check_code.txt"
        
        main_file_local = os.path.join(temp_dir, "file_processor.js")
        test_file_local = os.path.join(temp_dir, "file_processor.test.js")
        syntax_check_local = os.path.join(temp_dir, "syntax_check_code.txt")
        
        try:
            copy_from_env(main_file_container, main_file_local)
            copy_from_env(test_file_container, test_file_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not access required files: {e}"}
        
        # Try to get syntax check result
        try:
            copy_from_env(syntax_check_container, syntax_check_local)
        except:
            logger.warning("Could not access syntax check result")
        
        # Read file contents
        if not os.path.exists(main_file_local):
            return {"passed": False, "score": 0, "feedback": "Main file not found"}
        
        main_content = read_file_content(main_file_local)
        test_content = read_file_content(test_file_local) if os.path.exists(test_file_local) else ""
        
        if not main_content:
            return {"passed": False, "score": 0, "feedback": "Main file is empty"}
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # ===== Criterion 1: Verify callback patterns REMOVED =====
        callback_patterns = [
            (r'function\s*\(\s*err\s*,', 'function(err, ...)'),
            (r'callback\s*\(', 'callback('),
            (r',\s*callback\s*\)', ', callback)'),
        ]
        
        found_callbacks = []
        for pattern, description in callback_patterns:
            matches = re.findall(pattern, main_content, re.IGNORECASE)
            if matches:
                found_callbacks.append(f"{description} (found {len(matches)}x)")
        
        if not found_callbacks:
            criteria_passed += 1
            feedback_parts.append("✅ No callback patterns remain")
        else:
            feedback_parts.append(f"❌ Old callback patterns still exist: {', '.join(found_callbacks[:2])}")
        
        # ===== Criterion 2: Verify async/await patterns ADDED =====
        async_count = main_content.count('async')
        await_count = main_content.count('await')
        
        # Check for various Promise patterns
        promise_patterns = [
            r'return\s+new\s+Promise',
            r'Promise\.(resolve|reject|all)',
            r'async\s+function',
            r'async\s+\w+\s*\(',
        ]
        
        has_promise = any(re.search(p, main_content) for p in promise_patterns)
        
        async_await_ok = (async_count >= 2 and await_count >= 2) or (async_count >= 1 and has_promise)
        
        if async_await_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Async/await patterns present (async: {async_count}, await: {await_count})")
        else:
            feedback_parts.append(f"❌ Insufficient async/await patterns (async: {async_count}, await: {await_count}, expected ≥2 each)")
        
        # ===== Criterion 3: Verify error handling preserved =====
        error_handling_patterns = [
            (r'try\s*\{', 'try block'),
            (r'catch\s*\(', 'catch block'),
            (r'\.catch\s*\(', '.catch() handler'),
            (r'throw\s+', 'throw statement'),
            (r'reject\s*\(', 'reject() call'),
        ]
        
        found_error_handling = []
        for pattern, description in error_handling_patterns:
            if re.search(pattern, main_content):
                found_error_handling.append(description)
        
        if len(found_error_handling) >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Error handling preserved ({', '.join(found_error_handling[:2])})")
        else:
            if found_error_handling:
                feedback_parts.append(f"⚠️  Limited error handling found: {', '.join(found_error_handling)}")
            else:
                feedback_parts.append("❌ No error handling found (need try/catch or .catch())")
        
        # ===== Criterion 4: Verify test file updated =====
        test_has_async = 'async' in test_content
        test_has_await = 'await' in test_content
        # Old test pattern should be removed
        test_has_done = 'function(done)' in test_content or 'function (done)' in test_content
        
        if test_has_async and test_has_await and not test_has_done:
            criteria_passed += 1
            feedback_parts.append("✅ Test file updated to async/await")
        elif test_has_async or test_has_await:
            criteria_passed += 0.5  # Partial credit
            feedback_parts.append("⚠️  Test file partially updated (has async/await but may still have callback patterns)")
        else:
            feedback_parts.append("❌ Test file not updated to use async/await")
        
        # ===== Criterion 5: Syntax validation =====
        syntax_valid = False
        
        # Check if we have syntax check result from export script
        if os.path.exists(syntax_check_local):
            try:
                with open(syntax_check_local, 'r') as f:
                    exit_code = f.read().strip()
                if exit_code == '0':
                    syntax_valid = True
            except:
                pass
        
        # Fallback: basic syntax checks
        if not syntax_valid:
            # Check for basic syntax issues
            has_unmatched_braces = main_content.count('{') != main_content.count('}')
            has_unmatched_parens = main_content.count('(') != main_content.count(')')
            
            if not has_unmatched_braces and not has_unmatched_parens:
                syntax_valid = True
        
        if syntax_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Code is syntactically valid")
        else:
            feedback_parts.append("❌ Syntax errors detected")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # 80% threshold (4/5 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        if passed:
            summary = f"Successfully migrated from callbacks to async/await ({criteria_passed}/{total_criteria} criteria)"
        else:
            summary = f"Migration incomplete ({criteria_passed}/{total_criteria} criteria, need {0.8 * total_criteria})"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"{summary} | {feedback}"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
