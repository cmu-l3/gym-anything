#!/usr/bin/env python3
"""
Verifier for Batch Regex Refactor task
Checks if callback-style API calls were correctly converted to Promise-style
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def read_file_safe(filepath: str) -> str:
    """Safely read file content"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        logger.error(f"Error reading {filepath}: {e}")
        return ""


def verify_old_pattern_removed(content: str) -> tuple:
    """
    Check that old callback pattern is removed
    Returns: (success, count_remaining, feedback)
    """
    # Old pattern: apiClient.fetchUser(userId, function(error, user) {
    # Be flexible with whitespace and line breaks
    old_pattern = r'apiClient\.fetchUser\s*\([^)]+,\s*function\s*\([^)]*\)\s*\{'
    matches = re.findall(old_pattern, content, re.MULTILINE | re.DOTALL)
    
    count = len(matches)
    if count > 0:
        return False, count, f"Found {count} old callback pattern(s) still present"
    
    return True, 0, "Old callback pattern successfully removed"


def verify_promise_pattern_added(content: str) -> tuple:
    """
    Check that new Promise pattern is present
    Returns: (success, count, feedback)
    """
    # New pattern: apiClient.fetchUser(...).then(
    promise_pattern = r'apiClient\.fetchUser\s*\([^)]+\)\s*\.then\s*\('
    matches = re.findall(promise_pattern, content, re.MULTILINE)
    
    count = len(matches)
    if count == 0:
        return False, 0, "No Promise pattern found (.then() missing)"
    
    return True, count, f"Found {count} Promise pattern(s) with .then()"


def verify_error_handling_preserved(content: str) -> tuple:
    """
    Check that .catch() error handling is present
    Returns: (success, count, feedback)
    """
    # Check for .catch() blocks
    catch_pattern = r'\.catch\s*\(\s*\w+\s*=>'
    matches = re.findall(catch_pattern, content, re.MULTILINE)
    
    count = len(matches)
    if count == 0:
        return False, 0, "No error handling found (.catch() missing)"
    
    return True, count, f"Error handling preserved with {count} .catch() block(s)"


def verify_console_statements_present(content: str) -> tuple:
    """
    Verify that console.log/console.error statements are still present
    Returns: (success, has_log, has_error, feedback)
    """
    has_log = 'console.log' in content
    has_error = 'console.error' in content
    
    if not has_log and not has_error:
        return False, False, False, "Console statements missing (may have been accidentally removed)"
    
    return True, has_log, has_error, f"Console statements present (log: {has_log}, error: {has_error})"


def verify_file(filepath: str, filename: str) -> dict:
    """
    Verify a single file was correctly refactored
    
    Returns:
        dict with keys: success, score, details, feedback
    """
    if not os.path.exists(filepath):
        return {
            "success": False,
            "score": 0,
            "details": {},
            "feedback": f"File not found: {filename}"
        }
    
    content = read_file_safe(filepath)
    if not content or len(content) < 50:
        return {
            "success": False,
            "score": 0,
            "details": {},
            "feedback": f"File is empty or unreadable: {filename}"
        }
    
    # Check all criteria
    old_removed, old_count, old_feedback = verify_old_pattern_removed(content)
    promise_added, promise_count, promise_feedback = verify_promise_pattern_added(content)
    error_handling, catch_count, error_feedback = verify_error_handling_preserved(content)
    console_ok, has_log, has_error, console_feedback = verify_console_statements_present(content)
    
    # Calculate criteria passed (4 main criteria)
    criteria_passed = sum([
        old_removed,
        promise_added,
        error_handling,
        console_ok
    ])
    
    file_score = (criteria_passed / 4) * 100
    file_success = criteria_passed >= 3  # Need at least 3 out of 4 criteria
    
    details = {
        "old_pattern_removed": old_removed,
        "old_count_remaining": old_count,
        "promise_pattern_added": promise_added,
        "promise_count": promise_count,
        "error_handling_present": error_handling,
        "catch_count": catch_count,
        "console_statements_ok": console_ok
    }
    
    feedback_lines = [
        f"{'✅' if old_removed else '❌'} {old_feedback}",
        f"{'✅' if promise_added else '❌'} {promise_feedback}",
        f"{'✅' if error_handling else '❌'} {error_feedback}",
        f"{'✅' if console_ok else '⚠️'} {console_feedback}"
    ]
    
    return {
        "success": file_success,
        "score": file_score,
        "details": details,
        "feedback": " | ".join(feedback_lines)
    }


def verify_batch_regex_refactor(traj, env_info, task_info):
    """
    Main verification function for batch_regex_refactor@1
    
    Checks that at least 2 out of 3 target files were correctly refactored
    from callback-style to Promise-style API calls.
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='regex_refactor_verify_')
    
    try:
        # Target files that should be modified
        target_files = [
            "user-service.js",
            "profile-manager.js",
            "auth-handler.js"
        ]
        
        container_export_dir = "/tmp/batch_regex_export"
        results = {}
        
        # Copy and verify each target file
        for filename in target_files:
            container_path = f"{container_export_dir}/{filename}"
            local_path = os.path.join(temp_dir, filename)
            
            try:
                copy_from_env(container_path, local_path)
                result = verify_file(local_path, filename)
                results[filename] = result
                
                logger.info(f"\n{'='*60}")
                logger.info(f"File: {filename}")
                logger.info(f"Success: {result['success']} | Score: {result['score']:.0f}%")
                logger.info(f"Feedback: {result['feedback']}")
                logger.info(f"{'='*60}")
                
            except Exception as e:
                logger.error(f"Failed to verify {filename}: {e}")
                results[filename] = {
                    "success": False,
                    "score": 0,
                    "details": {},
                    "feedback": f"Failed to copy or verify file: {str(e)}"
                }
        
        # Calculate overall results
        total_files = len(target_files)
        successful_files = sum(1 for r in results.values() if r["success"])
        average_score = sum(r["score"] for r in results.values()) / total_files if total_files > 0 else 0
        
        # Pass if at least 2 out of 3 files are successfully refactored
        overall_success = successful_files >= 2
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Results: {successful_files}/{total_files} files correctly refactored")
        feedback_parts.append(f"Average score: {average_score:.0f}%")
        feedback_parts.append("")
        
        for filename, result in results.items():
            status = "✅ PASS" if result["success"] else "❌ FAIL"
            feedback_parts.append(f"{status} {filename} ({result['score']:.0f}%)")
            feedback_parts.append(f"  {result['feedback']}")
        
        if overall_success:
            feedback_parts.insert(0, "✅ Task completed successfully!")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete. Need at least 2 files correctly refactored, got {successful_files}")
        
        final_feedback = "\n".join(feedback_parts)
        
        logger.info(f"\n{'='*60}")
        logger.info(f"FINAL RESULT")
        logger.info(f"Success: {overall_success}")
        logger.info(f"Score: {average_score:.0f}%")
        logger.info(f"Files Passed: {successful_files}/{total_files}")
        logger.info(f"{'='*60}")
        
        return {
            "passed": overall_success,
            "score": int(average_score),
            "feedback": final_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
