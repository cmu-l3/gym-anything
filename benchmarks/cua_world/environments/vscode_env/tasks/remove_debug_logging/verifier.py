#!/usr/bin/env python3
"""
Verifier for Remove Debug Logging task
Checks that debug print statements are removed while preserving legitimate logging
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


def count_debug_prints(content: str) -> int:
    """Count print statements containing 'DEBUG' (case-insensitive)"""
    # Match print statements with DEBUG in them
    # Handles: print("DEBUG: ..."), print(f"DEBUG: ..."), print('DEBUG: ...')
    pattern = re.compile(r'print\s*\([^)]*DEBUG[^)]*\)', re.IGNORECASE)
    matches = pattern.findall(content)
    return len(matches)


def count_legitimate_prints(content: str) -> int:
    """Count total print statements (for logger.py verification)"""
    # Count all print( occurrences
    return content.count('print(')


def check_function_exists(content: str, function_pattern: str) -> bool:
    """Check if a function/class definition exists"""
    return function_pattern in content


def verify_debug_cleanup(traj, env_info, task_info):
    """
    Verify that debug print statements were removed correctly.
    
    Checks:
    1. All debug prints removed from application files (processor, worker, config, utils)
    2. Legitimate logging preserved in logger.py
    3. Test prints preserved
    4. Functions not accidentally deleted
    
    Scoring:
    - 100: All debug prints removed, legitimate code preserved
    - 70-90: Most debug prints removed (1-3 remaining)
    - 40-60: Partial cleanup (4-10 remaining)
    - 0-30: Minimal progress or legitimate code damaged
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_debug_')

    try:
        # Files to check for debug prints removal
        app_files = {
            'processor.py': {'initial_debug': 6, 'functions': ['def process_batch', 'def validate_input']},
            'worker.py': {'initial_debug': 6, 'functions': ['class Worker', 'def start', 'def _run']},
            'config.py': {'initial_debug': 4, 'functions': ['class Config', 'def validate']},
            'utils.py': {'initial_debug': 4, 'functions': ['def retry_operation']}
        }

        metadata = {
            "debug_prints_remaining": 0,
            "files_checked": [],
            "legitimate_prints_preserved": False,
            "test_prints_preserved": False,
            "functions_deleted": False,
            "files_missing": []
        }

        feedback_parts = []
        total_debug_prints = 0
        files_processed = 0

        # Check each application file
        for filename, file_info in app_files.items():
            container_path = f"/home/ga/workspace/data_processor/src/{filename}"
            local_path = os.path.join(temp_dir, filename)

            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    metadata["files_missing"].append(filename)
                    feedback_parts.append(f"❌ {filename} missing or empty")
                    continue

                with open(local_path, 'r', encoding='utf-8') as f:
                    content = f.read()

                metadata["files_checked"].append(filename)
                files_processed += 1

                # Count remaining debug prints
                debug_count = count_debug_prints(content)
                total_debug_prints += debug_count

                if debug_count > 0:
                    feedback_parts.append(f"⚠️  {filename}: {debug_count} debug print(s) remain")

                # Check that functions still exist
                for func_pattern in file_info['functions']:
                    if not check_function_exists(content, func_pattern):
                        metadata["functions_deleted"] = True
                        feedback_parts.append(f"❌ {filename}: '{func_pattern}' deleted or modified")
                        return {
                            "passed": False,
                            "score": 0,
                            "feedback": f"Critical code deleted in {filename}",
                            "metadata": metadata
                        }

            except Exception as e:
                logger.warning(f"Failed to verify {filename}: {e}")
                metadata["files_missing"].append(filename)
                feedback_parts.append(f"❌ {filename} could not be read")

        metadata["debug_prints_remaining"] = total_debug_prints

        # Verify legitimate logging is preserved in logger.py
        logger_path = "/home/ga/workspace/data_processor/src/logger.py"
        local_logger = os.path.join(temp_dir, "logger.py")

        try:
            copy_from_env(logger_path, local_logger)
            
            if os.path.exists(local_logger):
                with open(local_logger, 'r', encoding='utf-8') as f:
                    logger_content = f.read()

                legitimate_print_count = count_legitimate_prints(logger_content)
                
                # Should have at least 3 legitimate print statements (originally 5)
                if legitimate_print_count >= 3:
                    metadata["legitimate_prints_preserved"] = True
                    feedback_parts.append(f"✅ logger.py preserved ({legitimate_print_count} prints)")
                else:
                    feedback_parts.append(f"❌ logger.py damaged ({legitimate_print_count} prints, expected 5)")
                    return {
                        "passed": False,
                        "score": 20,
                        "feedback": "Legitimate logging code was removed from logger.py",
                        "metadata": metadata
                    }
            else:
                feedback_parts.append("❌ logger.py missing")
                return {
                    "passed": False,
                    "score": 10,
                    "feedback": "logger.py was deleted or moved",
                    "metadata": metadata
                }
        except Exception as e:
            logger.warning(f"Failed to verify logger.py: {e}")
            feedback_parts.append("⚠️  Could not verify logger.py")

        # Verify test file is untouched
        test_path = "/home/ga/workspace/data_processor/tests/test_processor.py"
        local_test = os.path.join(temp_dir, "test_processor.py")

        try:
            copy_from_env(test_path, local_test)
            
            if os.path.exists(local_test):
                with open(local_test, 'r', encoding='utf-8') as f:
                    test_content = f.read()

                test_print_count = count_legitimate_prints(test_content)
                
                # Should have at least 2 print statements
                if test_print_count >= 2:
                    metadata["test_prints_preserved"] = True
                    feedback_parts.append("✅ Test file preserved")
                else:
                    feedback_parts.append("⚠️  Test file may have been modified")
        except Exception as e:
            logger.warning(f"Failed to verify test file: {e}")

        # Calculate score based on results
        if files_processed == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files could be verified",
                "metadata": metadata
            }

        # Scoring logic
        if total_debug_prints == 0 and metadata["legitimate_prints_preserved"]:
            return {
                "passed": True,
                "score": 100,
                "feedback": "✅ All debug prints removed, legitimate code preserved | " + " | ".join(feedback_parts),
                "metadata": metadata
            }
        elif total_debug_prints <= 2 and metadata["legitimate_prints_preserved"]:
            return {
                "passed": False,
                "score": 85,
                "feedback": f"⚠️  {total_debug_prints} debug print(s) still remain | " + " | ".join(feedback_parts),
                "metadata": metadata
            }
        elif total_debug_prints <= 5 and metadata["legitimate_prints_preserved"]:
            return {
                "passed": False,
                "score": 70,
                "feedback": f"⚠️  {total_debug_prints} debug print(s) still remain | " + " | ".join(feedback_parts),
                "metadata": metadata
            }
        elif total_debug_prints <= 10:
            return {
                "passed": False,
                "score": 50,
                "feedback": f"❌ {total_debug_prints} debug prints remain - task incomplete | " + " | ".join(feedback_parts),
                "metadata": metadata
            }
        else:
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ {total_debug_prints} debug prints remain - minimal progress | " + " | ".join(feedback_parts),
                "metadata": metadata
            }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "metadata": {}
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
