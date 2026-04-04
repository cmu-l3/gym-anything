#!/usr/bin/env python3
"""
Verifier for Code Archaeology task (understand_confusing_code)
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_code_archaeology(traj, env_info, task_info):
    """
    Verify that the user successfully investigated the confusing code
    and documented their findings in INVESTIGATION.md.
    
    Checks:
    1. INVESTIGATION.md file exists with substantial content
    2. Contains commit hash (a3f82b4 or full hash)
    3. Mentions author Sarah Chen
    4. Explains leap year/timezone/double-discount bug context
    5. Makes correct recommendation (DO_NOT_CHANGE/NOT SAFE because migration not done)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_archaeology_')
    
    try:
        investigation_path = "/home/ga/workspace/pricing-project/INVESTIGATION.md"
        local_investigation = os.path.join(temp_dir, "INVESTIGATION.md")
        
        # Copy investigation file
        try:
            copy_from_env(investigation_path, local_investigation)
        except Exception as e:
            logger.warning(f"Failed to copy INVESTIGATION.md: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ INVESTIGATION.md not found. Create this file in the workspace root (/home/ga/workspace/pricing-project/INVESTIGATION.md) with your findings."
            }
        
        # Check file exists and has content
        if not os.path.exists(local_investigation):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ INVESTIGATION.md not found in workspace root"
            }
        
        file_size = os.path.getsize(local_investigation)
        if file_size < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ INVESTIGATION.md too short ({file_size} bytes). Need substantial documentation of findings."
            }
        
        # Read content
        content = read_file_content(local_investigation)
        content_lower = content.lower()
        
        # Initialize checks
        checks = {
            "has_commit_hash": False,
            "has_author": False,
            "has_explanation": False,
            "has_recommendation": False,
            "correct_understanding": False
        }
        
        feedback_parts = []
        
        # Check 1: Contains commit hash
        # Look for short hash a3f82b4 or any git hash format
        if re.search(r'a3f82b4', content, re.IGNORECASE) or \
           re.search(r'\b[a-f0-9]{7,40}\b', content):
            checks["has_commit_hash"] = True
            feedback_parts.append("✅ Commit hash identified")
        else:
            feedback_parts.append("❌ Missing commit hash (use Git Blame to find it)")
        
        # Check 2: Mentions the author Sarah Chen
        if re.search(r'sarah|chen', content_lower):
            checks["has_author"] = True
            feedback_parts.append("✅ Author identified")
        else:
            feedback_parts.append("❌ Missing author name (check commit author)")
        
        # Check 3: Explains the bug context (leap year, timezone, double-discount, 2020)
        context_keywords = [
            r'leap\s*year',
            r'2020',
            r'timezone',
            r'double[- ]?discount',
            r'pricing\s+bug',
            r'applied\s+twice',
            r'dst|daylight',
            r'stored.*price|price.*stored',
            r'database|db'
        ]
        
        context_matches = sum(1 for pattern in context_keywords if re.search(pattern, content_lower))
        
        if context_matches >= 3:
            checks["has_explanation"] = True
            feedback_parts.append(f"✅ Bug context explained (found {context_matches} key concepts)")
        else:
            feedback_parts.append(f"❌ Incomplete explanation (found {context_matches}/3+ key concepts). Read commit message and issue #247")
        
        # Check 4: Has a clear recommendation
        if re.search(r'safe[_\s]*to[_\s]*refactor|do[_\s]*not[_\s]*change|not\s+safe|recommendation', content_lower):
            checks["has_recommendation"] = True
            feedback_parts.append("✅ Recommendation provided")
        else:
            feedback_parts.append("❌ Missing clear recommendation (SAFE_TO_REFACTOR or DO_NOT_CHANGE)")
        
        # Check 5: Correct understanding - should recommend NOT changing
        # Look for indicators they understand it should NOT be changed yet
        do_not_change_indicators = [
            r'do[_\s]*not[_\s]*change',
            r'not\s+safe',
            r'keep.*workaround',
            r'maintain.*workaround',
            r'wait.*migration',
            r'data\s+migration.*not.*done',
            r'2025.*migration',
            r'until.*migration',
            r'issue.*312'
        ]
        
        safe_to_refactor_indicators = [
            r'safe[_\s]*to[_\s]*refactor',
            r'can\s+be\s+removed',
            r'okay\s+to\s+change',
            r'remove.*code'
        ]
        
        # Check if they incorrectly think it's safe to refactor
        has_safe_refactor = any(re.search(pattern, content_lower) for pattern in safe_to_refactor_indicators)
        has_do_not_change = any(re.search(pattern, content_lower) for pattern in do_not_change_indicators)
        
        if has_do_not_change and not has_safe_refactor:
            checks["correct_understanding"] = True
            feedback_parts.append("✅ Correct recommendation: code should NOT be changed yet (migration not done)")
        elif has_safe_refactor and not has_do_not_change:
            feedback_parts.append("❌ Incorrect recommendation: code should NOT be changed (data migration scheduled for 2025, issue #312)")
        elif has_do_not_change and has_safe_refactor:
            # Ambiguous - check which is stronger
            checks["correct_understanding"] = True
            feedback_parts.append("⚠️ Ambiguous recommendation, but mentions waiting for migration")
        else:
            feedback_parts.append("❌ Unclear recommendation: specify if code should be changed or not")
        
        # Calculate score
        passed_count = sum(checks.values())
        score = int((passed_count / len(checks)) * 100)
        passed = score >= 80  # Need 4/5 criteria
        
        # Build detailed feedback
        feedback = " | ".join(feedback_parts)
        
        # Add summary based on score
        if score == 100:
            summary = "🎉 Excellent code archaeology! You found all key information and made the correct recommendation."
        elif score >= 80:
            summary = "✅ Good investigation! You found the essential information."
        elif score >= 60:
            summary = "⚠️ Partial investigation. Check commit messages and issue #247 for more context."
        else:
            summary = "❌ Investigation incomplete. Use Git Blame, read commit messages, and check .github/issues/"
        
        final_feedback = f"{summary} | {feedback}"
        
        return {
            "passed": passed,
            "score": score,
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
