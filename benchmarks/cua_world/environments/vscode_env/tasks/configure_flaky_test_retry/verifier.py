#!/usr/bin/env python3
"""
Verifier for Configure Flaky Test Retry task
"""

import sys
import os
import re
import logging
import tempfile
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_flaky_test_config(traj, env_info, task_info):
    """
    Verify that flaky test retry configuration was properly set up.
    
    Checks:
    1. Jest config has retry configuration (25 points)
    2. fetchUserData timeout increased to ≥10000ms (20 points)
    3. processWebhook has retry logic (15 points)
    4. Logging statements added (15 points)
    5. FLAKY_TESTS.md created with proper content (25 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace_base = "/home/ga/workspace/flaky-test-project"
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: Jest config has retry configuration (25 points)
    jest_config_path = f"{workspace_base}/jest.config.js"
    jest_config_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    
    try:
        copy_from_env(jest_config_path, jest_config_temp.name)
        
        if os.path.exists(jest_config_temp.name) and os.path.getsize(jest_config_temp.name) > 0:
            config_content = read_file_content(jest_config_temp.name)
            
            # Look for retry-related configuration
            retry_patterns = [
                r'\bretries\s*:\s*\d+',                    # retries: 2
                r'\bretry\s*:\s*\d+',                      # retry: 2
                r'retryTimes',                             # retryTimes
                r'jest-retries',                           # jest-retries package
                r'testRunner.*retry',                      # custom test runner with retry
                r'maxRetries',                             # maxRetries
                r'testRetries',                            # testRetries
            ]
            
            retry_found = False
            for pattern in retry_patterns:
                if re.search(pattern, config_content, re.IGNORECASE):
                    retry_found = True
                    match = re.search(pattern, config_content, re.IGNORECASE)
                    logger.info(f"Found retry configuration: {match.group(0)}")
                    break
            
            if retry_found:
                logger.info("✓ Jest config has retry configuration")
                feedback_parts.append("✅ Jest config has retry configuration")
                score += 25
            else:
                logger.warning("✗ No retry configuration found in jest.config.js")
                feedback_parts.append("❌ No retry configuration in jest.config.js")
        else:
            logger.error("✗ jest.config.js not found or empty")
            feedback_parts.append("❌ jest.config.js not found")
    except Exception as e:
        logger.error(f"Error checking jest.config.js: {e}")
        feedback_parts.append(f"❌ Error reading jest.config.js: {str(e)}")
    finally:
        if os.path.exists(jest_config_temp.name):
            os.unlink(jest_config_temp.name)
    
    # Check 2, 3, 4: Test file modifications
    test_file_path = f"{workspace_base}/tests/api.test.js"
    test_file_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    
    try:
        copy_from_env(test_file_path, test_file_temp.name)
        
        if os.path.exists(test_file_temp.name) and os.path.getsize(test_file_temp.name) > 0:
            test_content = read_file_content(test_file_temp.name)
            
            # Check 2a: Timeout increased for fetchUserData (20 points)
            # Look for fetchUserData test with timeout parameter
            # Pattern: test('...fetchUserData...', async () => {...}, TIMEOUT)
            
            # Try to find the test block
            fetch_test_pattern = r"test\s*\(\s*['\"].*fetchUserData.*['\"].*?=>.*?\}\s*,\s*(\d+)\s*\)"
            fetch_match = re.search(fetch_test_pattern, test_content, re.DOTALL)
            
            timeout_ok = False
            if fetch_match:
                timeout = int(fetch_match.group(1))
                if timeout >= 10000:
                    logger.info(f"✓ fetchUserData timeout increased to {timeout}ms")
                    feedback_parts.append(f"✅ fetchUserData timeout: {timeout}ms (≥10000ms)")
                    score += 20
                    timeout_ok = True
                else:
                    logger.warning(f"✗ fetchUserData timeout only {timeout}ms (need ≥10000ms)")
                    feedback_parts.append(f"❌ fetchUserData timeout: {timeout}ms (need ≥10000ms)")
            
            # Alternative: Check for jest.setTimeout inside fetchUserData test
            if not timeout_ok:
                # Find the fetchUserData test block
                fetch_test_start = test_content.find("test('fetchUserData")
                if fetch_test_start == -1:
                    fetch_test_start = test_content.find('test("fetchUserData')
                if fetch_test_start == -1:
                    fetch_test_start = test_content.find('test(`fetchUserData')
                
                if fetch_test_start != -1:
                    # Look for next test or end of file
                    next_test = test_content.find("test(", fetch_test_start + 10)
                    if next_test == -1:
                        next_test = len(test_content)
                    
                    fetch_test_block = test_content[fetch_test_start:next_test]
                    
                    # Look for jest.setTimeout with high value
                    setTimeout_match = re.search(r'jest\.setTimeout\s*\(\s*(\d+)\s*\)', fetch_test_block)
                    if setTimeout_match:
                        timeout = int(setTimeout_match.group(1))
                        if timeout >= 10000:
                            logger.info(f"✓ fetchUserData timeout set via jest.setTimeout: {timeout}ms")
                            feedback_parts.append(f"✅ fetchUserData timeout (jest.setTimeout): {timeout}ms")
                            score += 20
                            timeout_ok = True
            
            if not timeout_ok:
                logger.warning("✗ fetchUserData timeout not properly increased")
                feedback_parts.append("❌ fetchUserData timeout not increased to ≥10000ms")
            
            # Check 2b: Retry logic for processWebhook (15 points)
            webhook_retry = False
            
            # Find processWebhook test block
            webhook_test_start = test_content.find("test('processWebhook")
            if webhook_test_start == -1:
                webhook_test_start = test_content.find('test("processWebhook')
            if webhook_test_start == -1:
                webhook_test_start = test_content.find('test(`processWebhook')
            
            if webhook_test_start != -1:
                # Look for next test or end of file
                next_test = test_content.find("test(", webhook_test_start + 10)
                if next_test == -1:
                    next_test = len(test_content)
                
                webhook_test_block = test_content[webhook_test_start:next_test]
                
                # Look for retry patterns
                retry_patterns = [
                    r'jest\.retryTimes\s*\(\s*\d+\s*\)',           # jest.retryTimes(2)
                    r'this\.retries\s*\(\s*\d+\s*\)',              # this.retries(2) - Mocha style
                    r'retryTimes\s*:\s*\d+',                       # retryTimes: 2
                    r'\.retry\s*\(\s*\d+\s*\)',                    # .retry(2)
                ]
                
                for pattern in retry_patterns:
                    if re.search(pattern, webhook_test_block):
                        webhook_retry = True
                        match = re.search(pattern, webhook_test_block)
                        logger.info(f"✓ processWebhook has retry logic: {match.group(0)}")
                        break
            
            if webhook_retry:
                feedback_parts.append("✅ processWebhook has retry logic")
                score += 15
            else:
                logger.warning("✗ No retry logic found for processWebhook test")
                feedback_parts.append("❌ No retry logic for processWebhook")
            
            # Check 2c: Logging added (15 points)
            logging_patterns = [
                r'console\.log.*[Aa]ttempt',          # console.log with "attempt"
                r'console\.log.*[Rr]etry',            # console.log with "retry"
                r'console\.log.*[Tt]est.*\d+',        # console.log with test attempt number
                r'console\.info.*[Aa]ttempt',         # console.info
                r'console\.warn.*[Rr]etry',           # console.warn
            ]
            
            logging_found = False
            for pattern in logging_patterns:
                if re.search(pattern, test_content, re.IGNORECASE):
                    logging_found = True
                    match = re.search(pattern, test_content, re.IGNORECASE)
                    logger.info(f"✓ Logging statement found: {match.group(0)[:50]}")
                    break
            
            if logging_found:
                feedback_parts.append("✅ Logging statements added")
                score += 15
            else:
                logger.warning("✗ No logging statements found")
                feedback_parts.append("❌ No logging statements found")
        else:
            logger.error("✗ tests/api.test.js not found or empty")
            feedback_parts.append("❌ tests/api.test.js not found")
    except Exception as e:
        logger.error(f"Error checking tests/api.test.js: {e}")
        feedback_parts.append(f"❌ Error reading tests/api.test.js: {str(e)}")
    finally:
        if os.path.exists(test_file_temp.name):
            os.unlink(test_file_temp.name)
    
    # Check 3: Documentation file created (25 points)
    doc_path = f"{workspace_base}/FLAKY_TESTS.md"
    doc_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.md')
    
    try:
        copy_from_env(doc_path, doc_temp.name)
        
        if os.path.exists(doc_temp.name) and os.path.getsize(doc_temp.name) > 0:
            doc_content = read_file_content(doc_temp.name)
            
            doc_checks = {
                'length': len(doc_content) >= 50,
                'test_names': any(name in doc_content for name in ['fetchUserData', 'processWebhook', 'fetch_user', 'process_webhook']),
                'retry_mention': bool(re.search(r'retry|retries', doc_content, re.IGNORECASE)),
                'date': any(year in doc_content for year in ['2024', '2025', '2026', str(datetime.now().year)])
            }
            
            doc_score = sum(doc_checks.values()) * 6.25  # 25 points / 4 checks
            score += int(doc_score)
            
            passed_checks = sum(doc_checks.values())
            logger.info(f"✓ FLAKY_TESTS.md created with {passed_checks}/4 required elements")
            
            check_details = []
            if doc_checks['length']:
                check_details.append("length≥50")
            if doc_checks['test_names']:
                check_details.append("test names")
            if doc_checks['retry_mention']:
                check_details.append("retry mention")
            if doc_checks['date']:
                check_details.append("date")
            
            feedback_parts.append(f"✅ FLAKY_TESTS.md ({passed_checks}/4: {', '.join(check_details)})")
        else:
            logger.warning("✗ FLAKY_TESTS.md not created")
            feedback_parts.append("❌ FLAKY_TESTS.md not created")
    except Exception as e:
        logger.warning(f"Error checking FLAKY_TESTS.md: {e}")
        feedback_parts.append("❌ FLAKY_TESTS.md not found")
    finally:
        if os.path.exists(doc_temp.name):
            os.unlink(doc_temp.name)
    
    # Final scoring
    score = min(score, max_score)  # Cap at 100
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/{max_score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
