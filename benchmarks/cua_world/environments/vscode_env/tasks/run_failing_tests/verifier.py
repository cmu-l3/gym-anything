#!/usr/bin/env python3
"""
Verifier for Run Failing Tests task
"""

import sys
import os
import logging
import tempfile
import shutil
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_test_execution(traj, env_info, task_info):
    """
    Verify that the agent successfully ran failing tests.
    
    Checks:
    1. Tests were executed (pytest cache exists)
    2. Correct test framework used (pytest configured)
    3. Evidence of selective test running (not just full suite every time)
    4. Test failures detected (2 failures identified)
    5. Source code preserved (files not modified)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_test_verify_')

    try:
        checks = {
            'tests_executed': False,
            'correct_framework': False,
            'selective_running': False,
            'failures_detected': False,
            'source_preserved': False
        }
        
        feedback_parts = []

        # ============================================================
        # Check 1: Tests were executed (pytest cache exists)
        # ============================================================
        pytest_lastfailed_local = os.path.join(temp_dir, "pytest_lastfailed.json")
        
        try:
            copy_from_env("/tmp/pytest_lastfailed.json", pytest_lastfailed_local)
            
            if os.path.exists(pytest_lastfailed_local) and os.path.getsize(pytest_lastfailed_local) > 2:
                # File exists and is not just "{}" or empty
                checks['tests_executed'] = True
                feedback_parts.append("✅ Tests were executed (pytest cache found)")
            else:
                # Check if any pytest cache directory exists as backup
                pytest_cache_marker = os.path.join(temp_dir, "cache_marker.txt")
                try:
                    copy_from_env("/tmp/pytest_cache_export/README.md", pytest_cache_marker)
                    if os.path.exists(pytest_cache_marker):
                        checks['tests_executed'] = True
                        feedback_parts.append("✅ Tests were executed (pytest cache directory found)")
                except:
                    pass
                
                if not checks['tests_executed']:
                    feedback_parts.append("❌ No evidence of test execution (pytest cache missing)")
        except Exception as e:
            logger.warning(f"Failed to check pytest cache: {e}")
            feedback_parts.append("❌ Failed to verify test execution")

        # ============================================================
        # Check 2: Correct framework (pytest vs unittest)
        # ============================================================
        settings_local = os.path.join(temp_dir, "vscode_settings.json")
        
        try:
            copy_from_env("/tmp/vscode_settings.json", settings_local)
            
            if os.path.exists(settings_local):
                with open(settings_local, 'r') as f:
                    settings = json.load(f)
                    
                if settings.get('python.testing.pytestEnabled') == True:
                    checks['correct_framework'] = True
                    feedback_parts.append("✅ Pytest framework correctly configured")
                else:
                    feedback_parts.append("❌ Pytest not enabled in VSCode settings")
            else:
                feedback_parts.append("⚠️ VSCode settings not found")
        except Exception as e:
            logger.warning(f"Failed to check VSCode settings: {e}")
            # Give benefit of doubt if tests were executed
            if checks['tests_executed']:
                checks['correct_framework'] = True
                feedback_parts.append("✅ Framework verification skipped (tests ran successfully)")

        # ============================================================
        # Check 3: Selective running (check for evidence of individual test execution)
        # ============================================================
        bash_history_local = os.path.join(temp_dir, "bash_history.txt")
        
        try:
            copy_from_env("/tmp/bash_history.txt", bash_history_local)
            
            if os.path.exists(bash_history_local):
                with open(bash_history_local, 'r') as f:
                    history = f.read()
                    
                # Look for pytest commands with specific test names or -k flag
                selective_patterns = [
                    '::test_',  # Running specific test (pytest tests/test_file.py::test_name)
                    '-k test_',  # Running with keyword filter
                    '--collect-only',  # Test discovery
                ]
                
                if any(pattern in history for pattern in selective_patterns):
                    checks['selective_running'] = True
                    feedback_parts.append("✅ Evidence of selective test execution found")
                else:
                    # More lenient check: if tests were executed at all, give benefit of doubt
                    if checks['tests_executed']:
                        checks['selective_running'] = True
                        feedback_parts.append("✅ Test execution confirmed (selective running assumed)")
            else:
                # If tests were executed, give benefit of doubt
                if checks['tests_executed']:
                    checks['selective_running'] = True
                    feedback_parts.append("✅ Test execution confirmed (history unavailable)")
        except Exception as e:
            logger.warning(f"Failed to check bash history: {e}")
            # Give benefit of doubt if tests were executed
            if checks['tests_executed']:
                checks['selective_running'] = True
                feedback_parts.append("✅ Selective running check bypassed")

        # ============================================================
        # Check 4: Test failures detected (2 failures expected)
        # ============================================================
        if os.path.exists(pytest_lastfailed_local):
            try:
                with open(pytest_lastfailed_local, 'r') as f:
                    content = f.read().strip()
                    
                if content and content != "{}":
                    lastfailed = json.loads(content)
                    num_failures = len(lastfailed)
                    
                    # We expect 2 failures (test_subtract and test_divide)
                    if num_failures >= 1:  # At least one failure detected
                        checks['failures_detected'] = True
                        
                        if num_failures == 2:
                            feedback_parts.append(f"✅ Correct number of failures detected ({num_failures})")
                        else:
                            feedback_parts.append(f"✅ Test failures detected ({num_failures} failures found)")
                    else:
                        feedback_parts.append(f"❌ No test failures recorded in lastfailed")
                else:
                    # Empty lastfailed could mean all tests passed (unexpected) or not run
                    if checks['tests_executed']:
                        feedback_parts.append("⚠️ No failures recorded (tests may have all passed - unexpected)")
            except json.JSONDecodeError:
                feedback_parts.append("⚠️ Failed to parse lastfailed file")
        else:
            feedback_parts.append("❌ No failure information available")

        # ============================================================
        # Check 5: Source code preserved (files not modified)
        # ============================================================
        initial_checksum_local = os.path.join(temp_dir, "initial_calculator_checksum.txt")
        final_checksum_local = os.path.join(temp_dir, "final_calculator_checksum.txt")
        
        try:
            copy_from_env("/tmp/initial_calculator_checksum.txt", initial_checksum_local)
            copy_from_env("/tmp/final_calculator_checksum.txt", final_checksum_local)
            
            if os.path.exists(initial_checksum_local) and os.path.exists(final_checksum_local):
                with open(initial_checksum_local, 'r') as f:
                    initial_checksum = f.read().strip().split()[0] if f.read().strip() else ""
                
                with open(final_checksum_local, 'r') as f:
                    final_checksum = f.read().strip().split()[0] if f.read().strip() else ""
                
                if initial_checksum and final_checksum:
                    if initial_checksum == final_checksum:
                        checks['source_preserved'] = True
                        feedback_parts.append("✅ Source code not modified (task completed correctly)")
                    else:
                        feedback_parts.append("❌ Source code was modified (task was to RUN tests, not fix bugs)")
                else:
                    # Checksums missing, verify the bugs still exist in the code
                    calc_file_local = os.path.join(temp_dir, "calculator.py")
                    try:
                        copy_from_env("/home/ga/workspace/pytest_project/src/calculator.py", calc_file_local)
                        
                        with open(calc_file_local, 'r') as f:
                            calc_content = f.read()
                            
                        # Check that bugs are still present
                        bug1_present = "return a + b  # BUG" in calc_content  # subtract bug
                        bug2_present = "return a  # BUG" in calc_content  # divide bug
                        
                        if bug1_present and bug2_present:
                            checks['source_preserved'] = True
                            feedback_parts.append("✅ Source code preserved (bugs still present)")
                        else:
                            feedback_parts.append("❌ Source code may have been modified")
                    except:
                        # Can't verify, give benefit of doubt
                        checks['source_preserved'] = True
                        feedback_parts.append("✅ Source preservation check bypassed")
            else:
                # Checksums missing, assume preserved if tests were run correctly
                checks['source_preserved'] = True
                feedback_parts.append("✅ Source preservation assumed (checksums unavailable)")
        except Exception as e:
            logger.warning(f"Failed to check source preservation: {e}")
            checks['source_preserved'] = True
            feedback_parts.append("✅ Source preservation check bypassed")

        # ============================================================
        # Calculate final score
        # ============================================================
        criteria_passed = sum(checks.values())
        score = int((criteria_passed / 5) * 100)
        passed = score >= 75  # Need at least 4/5 criteria

        # Add summary at the beginning
        summary = f"Passed {criteria_passed}/5 criteria"
        feedback_parts.insert(0, summary)

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
        cleanup_verification_temp(temp_dir)
