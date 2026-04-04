#!/usr/bin/env python3
"""
Verifier for reproduce_ci_only_failure@1
Checks that the flaky test was fixed with proper synchronization
"""

import sys
import os
import re
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ci_fix(traj, env_info, task_info):
    """
    Verify that the CI flakiness was fixed with proper polling logic.
    
    Checks:
    1. Fixed time.sleep(2) was removed or is in a polling loop context
    2. Polling loop exists (while payment.status == "pending")
    3. Timeout mechanism exists
    4. Timeout value is reasonable (3-15 seconds)
    5. Comment explaining the fix exists (mentions race condition/async)
    
    Returns:
        dict: {'passed': bool, 'score': int, 'feedback': str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    container_path = "/home/ga/workspace/payment_service/tests/test_payment.py"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py', mode='w+')
    
    try:
        # Copy test file from container
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Test file not found or empty: {container_path}"
            }
        
        # Read file content
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if not content.strip():
            return {
                "passed": False,
                "score": 0,
                "feedback": "Test file is empty"
            }
        
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 5
        
        # Extract the test function for focused analysis
        test_func_match = re.search(
            r'def test_payment_processing\s*\([^)]*\):.*?(?=\ndef\s|\nclass\s|\Z)',
            content,
            re.DOTALL
        )
        
        if not test_func_match:
            return {
                "passed": False,
                "score": 0,
                "feedback": "test_payment_processing function not found or was deleted"
            }
        
        test_func_content = test_func_match.group(0)
        
        # Check 1: Fixed sleep(2) should be removed or only in polling context
        fixed_sleep_pattern = r'time\.sleep\s*\(\s*2\s*\)'
        fixed_sleep_matches = list(re.finditer(fixed_sleep_pattern, test_func_content))
        
        if fixed_sleep_matches:
            # Check if it's in a loop context (acceptable if polling)
            for match in fixed_sleep_matches:
                # Get surrounding context (100 chars before and after)
                start = max(0, match.start() - 150)
                end = min(len(test_func_content), match.end() + 150)
                context = test_func_content[start:end].lower()
                
                # If 'while' is not in context, it's still the old fixed sleep
                if 'while' not in context and 'for' not in context:
                    feedback_parts.append(
                        "❌ Fixed time.sleep(2) still present without polling loop"
                    )
                    return {
                        "passed": False,
                        "score": int((criteria_passed / total_criteria) * 100),
                        "feedback": " | ".join(feedback_parts)
                    }
        
        criteria_passed += 1
        feedback_parts.append("✅ Fixed sleep removed or properly contextualized")
        
        # Check 2: Polling loop exists
        polling_patterns = [
            r'while\s+.*payment\.status\s*==\s*["\']pending["\']',
            r'while\s+.*payment\.status\s*!=\s*["\']completed["\']',
            r'while\s+.*["\']pending["\']\s*==\s*.*payment\.status',
            r'while\s+.*\.status\s*==\s*["\']pending["\']'
        ]
        
        has_polling = any(
            re.search(pattern, test_func_content, re.IGNORECASE | re.DOTALL) 
            for pattern in polling_patterns
        )
        
        if not has_polling:
            feedback_parts.append(
                "❌ No polling loop detected (expected: while payment.status == 'pending')"
            )
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Polling loop implemented")
        
        # Check 3: Timeout mechanism exists
        timeout_patterns = [
            r'timeout\s*=\s*\d+',
            r'max_wait\s*=\s*\d+',
            r'max_time\s*=\s*\d+',
            r'time\.time\(\)\s*-\s*start\s*[<>]',
            r'elapsed\s*[<>]',
            r'start\s*=\s*time\.time\(\)'
        ]
        
        has_timeout = any(
            re.search(pattern, test_func_content, re.IGNORECASE) 
            for pattern in timeout_patterns
        )
        
        if not has_timeout:
            feedback_parts.append(
                "❌ No timeout mechanism (polling loop could hang forever)"
            )
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Timeout mechanism present")
        
        # Check 4: Timeout value is reasonable (3-15 seconds)
        timeout_value_patterns = [
            r'timeout\s*=\s*(\d+)',
            r'max_wait\s*=\s*(\d+)',
            r'max_time\s*=\s*(\d+)'
        ]
        
        timeout_val = None
        for pattern in timeout_value_patterns:
            match = re.search(pattern, test_func_content)
            if match:
                timeout_val = int(match.group(1))
                break
        
        if timeout_val is not None:
            if timeout_val < 3:
                feedback_parts.append(
                    f"❌ Timeout too short ({timeout_val}s < 3s minimum recommended)"
                )
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            elif timeout_val > 15:
                feedback_parts.append(
                    f"❌ Timeout too long ({timeout_val}s > 15s maximum recommended)"
                )
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                criteria_passed += 1
                feedback_parts.append(f"✅ Reasonable timeout value ({timeout_val}s)")
        else:
            # If using time.time() pattern without explicit variable, it's acceptable
            if 'time.time()' in test_func_content:
                criteria_passed += 1
                feedback_parts.append("✅ Timeout mechanism using time.time()")
            else:
                feedback_parts.append("❌ Could not determine timeout value")
                return {
                    "passed": False,
                    "score": int((criteria_passed / total_criteria) * 100),
                    "feedback": " | ".join(feedback_parts)
                }
        
        # Check 5: Comment explaining the fix
        comment_keywords = [
            'race condition', 'race-condition',
            'async', 'asynchronous',
            'thread', 'threading', 'background',
            'poll', 'polling',
            'wait for completion', 'wait for actual',
            'fixed sleep', 'fixed duration'
        ]
        
        # Extract all comments from the test function
        comments = re.findall(r'#[^\n]*', test_func_content)
        comment_text = ' '.join(comments).lower()
        
        has_explanation = any(keyword in comment_text for keyword in comment_keywords)
        
        if not has_explanation:
            feedback_parts.append(
                "❌ Missing explanation comment (should mention race condition/async/polling)"
            )
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Explanation comment present")
        
        # Bonus check: Small sleep in polling loop (good practice, not required)
        has_small_sleep = re.search(r'time\.sleep\s*\(\s*0\.\d+\s*\)', test_func_content)
        if has_small_sleep:
            feedback_parts.append("✅ Bonus: Efficient polling with small sleep interval")
        
        # All checks passed!
        score = int((criteria_passed / total_criteria) * 100)
        passed = (score == 100)  # Require all criteria for this task
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
