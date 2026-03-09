#!/usr/bin/env python3
"""
Verifier for Refine Regex Validator task
Checks that a test runner was created, regex was modified and documented, and all tests pass
"""

import os
import re
import subprocess
import sys
import logging
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that:
    1. A test runner script was created
    2. The regex pattern in validator.py was modified
    3. The regex is documented with comments
    4. All 12 test cases pass when the test runner is executed
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='regex_verify_')
    
    try:
        workspace_base = "/home/ga/workspace/email_validation"
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Copy all Python files from workspace to temp directory
        # We'll check for test runner files
        test_runner_patterns = ["test_*.py", "run_*.py", "*test*.py"]
        test_runners = []
        
        # Try to find test runner in standard locations
        for pattern in ["test_validator.py", "test_email.py", "run_tests.py", "test_validation.py", "run_validator.py"]:
            container_path = f"{workspace_base}/{pattern}"
            local_path = os.path.join(temp_dir, pattern)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    test_runners.append(local_path)
                    logger.info(f"Found test runner: {pattern}")
            except:
                pass
        
        # Also check /tmp for exported test runners
        for pattern in ["test_validator.py", "test_email.py", "run_tests.py", "test_validation.py", "run_validator.py", "test.py", "run.py"]:
            try:
                local_path = os.path.join(temp_dir, f"tmp_{pattern}")
                copy_from_env(f"/tmp/{pattern}", local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    test_runners.append(local_path)
                    logger.info(f"Found test runner in /tmp: {pattern}")
            except:
                pass
        
        # Criterion 1: Test runner exists
        if not test_runners:
            feedback_parts.append("❌ No test runner script found (expected test_*.py or run_*.py)")
            logger.error("No test runner found")
        else:
            criteria_passed += 1
            test_runner = test_runners[0]
            test_runner_name = os.path.basename(test_runner)
            feedback_parts.append(f"✅ Found test runner: {test_runner_name}")
            logger.info(f"Using test runner: {test_runner}")
        
        # Copy validator.py
        validator_local = os.path.join(temp_dir, "validator.py")
        try:
            copy_from_env(f"{workspace_base}/validator.py", validator_local)
        except:
            try:
                copy_from_env("/tmp/validator.py", validator_local)
            except:
                feedback_parts.append("❌ Could not copy validator.py")
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
        
        if not os.path.exists(validator_local):
            feedback_parts.append("❌ validator.py not found")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Read validator.py content
        with open(validator_local, 'r', encoding='utf-8') as f:
            validator_content = f.read()
        
        # Criterion 2: validator.py was modified (pattern is different from initial)
        initial_pattern = r'^[a-z0-9]+@[a-z]+\.[a-z]+$'
        if initial_pattern in validator_content:
            feedback_parts.append("❌ EMAIL_PATTERN was not modified from initial version")
        else:
            criteria_passed += 1
            # Extract the new pattern for logging
            pattern_match = re.search(r"EMAIL_PATTERN\s*=\s*r['\"](.+?)['\"]", validator_content, re.DOTALL)
            if pattern_match:
                new_pattern = pattern_match.group(1)
                # Truncate if very long
                display_pattern = new_pattern if len(new_pattern) < 60 else new_pattern[:60] + "..."
                feedback_parts.append(f"✅ Pattern was modified: {display_pattern}")
                logger.info(f"New pattern: {new_pattern}")
            else:
                feedback_parts.append("✅ Pattern was modified")
        
        # Criterion 3: Pattern has documentation comments
        # Look for comments near EMAIL_PATTERN definition
        lines = validator_content.split('\n')
        pattern_line_idx = None
        for i, line in enumerate(lines):
            if 'EMAIL_PATTERN' in line and '=' in line:
                pattern_line_idx = i
                break
        
        has_documentation = False
        if pattern_line_idx is not None:
            # Check 10 lines before and 5 lines after for comments
            start = max(0, pattern_line_idx - 10)
            end = min(len(lines), pattern_line_idx + 5)
            context_lines = lines[start:end]
            
            # Count substantive comment lines (not just # TODO)
            comment_lines = []
            for line in context_lines:
                stripped = line.strip()
                if stripped.startswith('#'):
                    # Exclude generic TODOs and empty comments
                    if stripped not in ['#', '# TODO', '# TODO:', '# FIXME', '# FIXME:']:
                        # Check it's not the exact original TODO
                        if 'Fix this regex pattern' not in stripped or len(comment_lines) > 0:
                            comment_lines.append(stripped)
            
            logger.info(f"Found {len(comment_lines)} comment lines near EMAIL_PATTERN")
            logger.info(f"Comments: {comment_lines}")
            
            if len(comment_lines) >= 2:
                has_documentation = True
        
        if has_documentation:
            criteria_passed += 1
            feedback_parts.append(f"✅ Pattern is documented with {len(comment_lines)} comment lines")
        else:
            feedback_parts.append("❌ Regex pattern lacks sufficient documentation (need at least 2 comment lines)")
        
        # Copy test_cases.txt
        test_cases_local = os.path.join(temp_dir, "test_cases.txt")
        try:
            copy_from_env(f"{workspace_base}/test_cases.txt", test_cases_local)
        except:
            try:
                copy_from_env("/tmp/test_cases.txt", test_cases_local)
            except:
                logger.warning("Could not copy test_cases.txt")
        
        # Criterion 4: Run the test runner and verify all tests pass
        if test_runners:
            try:
                test_runner = test_runners[0]
                logger.info(f"Running test runner: {test_runner}")
                
                # Run the test script from temp directory
                result = subprocess.run(
                    ['python3', test_runner],
                    cwd=temp_dir,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    env={**os.environ, 'PYTHONPATH': temp_dir}
                )
                
                output = result.stdout + result.stderr
                logger.info(f"Test runner output:\n{output}")
                
                # Check for success indicators
                output_lower = output.lower()
                
                # Multiple ways to detect success
                success_indicators = [
                    # Explicit success messages
                    '12/12' in output_lower and 'pass' in output_lower,
                    '12 / 12' in output_lower and 'pass' in output_lower,
                    'all 12 tests passed' in output_lower,
                    'all tests passed' in output_lower and '12' in output_lower,
                    # Exit code 0 and no failures
                    result.returncode == 0 and 'fail' not in output_lower and '0 failed' not in output_lower,
                ]
                
                # Count pass/fail indicators
                pass_count = len(re.findall(r'\bpass(?:ed)?\b', output_lower))
                fail_count = len(re.findall(r'\bfail(?:ed|ure)?\b', output_lower))
                
                # Also look for checkmarks or test result indicators
                checkmark_count = output.count('✓') + output.count('✔') + output.count('[PASS]')
                cross_count = output.count('✗') + output.count('✘') + output.count('[FAIL]')
                
                logger.info(f"Exit code: {result.returncode}, Pass mentions: {pass_count}, Fail mentions: {fail_count}")
                logger.info(f"Checkmarks: {checkmark_count}, Crosses: {cross_count}")
                
                # Determine success
                tests_passed = False
                
                if any(success_indicators):
                    tests_passed = True
                elif result.returncode == 0 and (pass_count >= 8 or checkmark_count >= 8) and fail_count == 0 and cross_count == 0:
                    tests_passed = True
                elif checkmark_count == 12 and cross_count == 0:
                    tests_passed = True
                
                if tests_passed:
                    criteria_passed += 1
                    feedback_parts.append("✅ All 12 test cases pass")
                else:
                    # Provide diagnostic info
                    if result.returncode != 0:
                        feedback_parts.append(f"❌ Test runner exited with error code {result.returncode}")
                    elif fail_count > 0 or cross_count > 0:
                        feedback_parts.append(f"❌ Some tests failed (detected {fail_count} failures)")
                    else:
                        feedback_parts.append("❌ Could not confirm all tests passed")
                    
                    # Include a snippet of output for debugging
                    output_snippet = output[:300] if len(output) > 300 else output
                    feedback_parts.append(f"Test output: {output_snippet}")
                
            except subprocess.TimeoutExpired:
                feedback_parts.append("❌ Test runner timed out after 15 seconds")
                logger.error("Test runner timed out")
            except Exception as e:
                feedback_parts.append(f"❌ Error running test runner: {str(e)}")
                logger.error(f"Error running test runner: {e}", exc_info=True)
        else:
            feedback_parts.append("❌ Cannot run tests - no test runner found")
        
        # Calculate final score and pass/fail
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final result: {criteria_passed}/{total_criteria} criteria passed")
        logger.info(f"Score: {score}, Passed: {passed}")
        
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
