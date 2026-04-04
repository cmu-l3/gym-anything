#!/usr/bin/env python3
"""
Verifier for investigate_customer_bug@1
Checks that agent correctly identified and documented the date filtering bug
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bug_investigation(traj, env_info, task_info):
    """
    Verify bug investigation and documentation.
    
    Checks:
    1. Correct file (date_utils.py) was modified
    2. Bug location identified (near the comparison line)
    3. Comment has marker (TODO/FIXME/BUG/XXX)
    4. Comment mentions it's a bug/error/problem
    5. Comment explains technical issue (end date exclusivity, off-by-one)
    6. Comment describes impact (missing transactions, wrong totals)
    
    Returns:
        dict with "passed", "score", "feedback" keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ FAILED: Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='bug_investigation_verify_')
    
    try:
        # Path to the file that should be modified
        container_path = "/tmp/bug_investigation_results/date_utils.py"
        local_path = os.path.join(temp_dir, "date_utils.py")
        
        # Copy file from container
        try:
            copy_from_env(container_path, local_path)
        except Exception as e:
            logger.error(f"Failed to copy date_utils.py: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ FAILED: Could not copy date_utils.py from results directory (error: {str(e)})"
            }
        
        # Check file exists and is readable
        if not check_file_exists(local_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FAILED: date_utils.py not found in results"
            }
        
        content = read_file_content(local_path)
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FAILED: Could not read date_utils.py content"
            }
        
        # Locate the buggy comparison line
        buggy_pattern = r'if\s+start\s*<=\s*txn_date\s*<\s*end\s*:'
        buggy_match = re.search(buggy_pattern, content)
        
        if not buggy_match:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FAILED: Could not locate buggy comparison line 'if start <= txn_date < end:'"
            }
        
        # Find line number of buggy code
        buggy_pos = buggy_match.start()
        buggy_line_num = content[:buggy_pos].count('\n') + 1
        
        # Extract context: ±5 lines around buggy line
        lines = content.split('\n')
        start_idx = max(0, buggy_line_num - 6)
        end_idx = min(len(lines), buggy_line_num + 5)
        context = '\n'.join(lines[start_idx:end_idx])
        
        # Initialize scoring
        criteria_checks = {}
        feedback_parts = []
        
        # Criterion 1: Has marker (TODO, FIXME, BUG, XXX)
        criteria_checks['has_marker'] = bool(re.search(
            r'#.*\b(TODO|FIXME|BUG|XXX)\b', 
            context, 
            re.IGNORECASE
        ))
        
        # Criterion 2: Mentions problem
        criteria_checks['mentions_problem'] = bool(re.search(
            r'#.*(bug|error|issue|problem|wrong|incorrect|broken)',
            context,
            re.IGNORECASE
        ))
        
        # Criterion 3: Explains technical detail
        criteria_checks['explains_technical'] = bool(re.search(
            r'#.*(end.?date|exclusive|inclusive|off.?by.?one|last.?day|boundary|comparison|<=|<)',
            context,
            re.IGNORECASE
        ))
        
        # Criterion 4: Describes impact
        criteria_checks['describes_impact'] = bool(re.search(
            r'#.*(missing|excluded|incorrect|wrong|transaction|total|export)',
            context,
            re.IGNORECASE
        ))
        
        # Calculate score with weighted criteria
        score = 0.0
        
        if criteria_checks['has_marker']:
            score += 0.30
            feedback_parts.append("✅ Comment has TODO/FIXME/BUG marker (30%)")
        else:
            feedback_parts.append("❌ Missing TODO/FIXME/BUG marker (0/30%)")
        
        if criteria_checks['mentions_problem']:
            score += 0.25
            feedback_parts.append("✅ Comment identifies this as a bug/error (25%)")
        else:
            feedback_parts.append("❌ Comment should identify this as a bug/error (0/25%)")
        
        if criteria_checks['explains_technical']:
            score += 0.30
            feedback_parts.append("✅ Comment explains technical issue (30%)")
        else:
            feedback_parts.append("❌ Comment should explain technical issue (end date exclusivity) (0/30%)")
        
        if criteria_checks['describes_impact']:
            score += 0.15
            feedback_parts.append("✅ Comment describes impact on users (15%)")
        else:
            feedback_parts.append("❌ Comment should describe impact (missing transactions) (0/15%)")
        
        # Convert to 0-100 scale
        score_100 = int(score * 100)
        
        # Determine pass/fail (85% threshold)
        passed = score >= 0.85
        
        # Build feedback message
        if passed:
            status = f"✅ SUCCESS (score: {score_100}%)"
        elif score >= 0.5:
            status = f"⚠️  PARTIAL SUCCESS (score: {score_100}%)"
        else:
            status = f"❌ FAILED (score: {score_100}%)"
        
        feedback = f"{status}\n\nCriteria breakdown:\n" + "\n".join(feedback_parts)
        
        # Add helpful hint if not passed
        if not passed:
            feedback += "\n\n💡 Hint: Your comment should include: (1) a marker like TODO/FIXME/BUG, (2) mention this is a bug/error, (3) explain the technical issue (using < instead of <=), and (4) describe the impact (transactions excluded)."
        
        return {
            "passed": passed,
            "score": score_100,
            "feedback": feedback,
            "metadata": {
                "buggy_line": buggy_line_num,
                "criteria_checks": criteria_checks,
                "context_examined": context[:200] + "..." if len(context) > 200 else context
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
