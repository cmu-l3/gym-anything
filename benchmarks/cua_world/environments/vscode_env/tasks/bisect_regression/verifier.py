#!/usr/bin/env python3
"""
Verifier for Bisect Regression task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bisect_regression(traj, env_info, task_info):
    """
    Verify that Git bisect was used to find the regression.
    
    Checks:
    1. BISECT_RESULTS.md file exists
    2. File contains a commit SHA
    3. SHA matches the actual bad commit (identified during setup)
    4. Results include commit message
    5. Results include files changed
    6. Results include some analysis/hypothesis
    7. Git bisect was properly cleaned up (no active BISECT_LOG)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='bisect_verify_')

    try:
        # Copy exported files
        results_file = os.path.join(temp_dir, "bisect_results.md")
        git_log_file = os.path.join(temp_dir, "git_log_bisect.txt")
        bisect_status_file = os.path.join(temp_dir, "bisect_log_active.txt")
        bad_commit_ref_file = os.path.join(temp_dir, "bad_commit_sha.txt")

        try:
            copy_from_env("/tmp/bisect_results.md", results_file)
        except Exception as e:
            logger.warning(f"Failed to copy bisect_results.md: {e}")

        try:
            copy_from_env("/tmp/git_log_bisect.txt", git_log_file)
        except Exception as e:
            logger.warning(f"Failed to copy git log: {e}")

        try:
            copy_from_env("/tmp/bisect_log_active.txt", bisect_status_file)
        except Exception as e:
            logger.warning(f"Failed to copy bisect status: {e}")

        try:
            copy_from_env("/tmp/bad_commit_sha.txt", bad_commit_ref_file)
        except Exception as e:
            logger.warning(f"Failed to copy bad commit reference: {e}")

        feedback_parts = []
        score = 0.0
        metadata = {}

        # Read the actual bad commit SHA (stored during setup)
        actual_bad_commit = None
        if os.path.exists(bad_commit_ref_file):
            with open(bad_commit_ref_file, 'r') as f:
                actual_bad_commit = f.read().strip()
                logger.info(f"Actual bad commit SHA: {actual_bad_commit}")
        else:
            # Fallback: search git log for the commit with the bug message
            if os.path.exists(git_log_file):
                with open(git_log_file, 'r') as f:
                    for line in f:
                        if 'refactor: clean up payment processing logic' in line.lower():
                            parts = line.split('|')
                            if parts:
                                actual_bad_commit = parts[0].strip()
                                logger.info(f"Found bad commit from git log: {actual_bad_commit}")
                                break

        # Check 1: BISECT_RESULTS.md exists and has content
        if not os.path.exists(results_file):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ BISECT_RESULTS.md not found. You must document your findings in /home/ga/workspace/payment-service/BISECT_RESULTS.md"
            }

        with open(results_file, 'r') as f:
            results_content = f.read()

        if not results_content or len(results_content) < 20 or 'File not created' in results_content:
            return {
                "passed": False,
                "score": 5,
                "feedback": "❌ BISECT_RESULTS.md is empty or invalid. Please document your git bisect findings."
            }

        feedback_parts.append("✓ BISECT_RESULTS.md exists")
        score += 15
        metadata['results_content_length'] = len(results_content)

        # Check 2: Find commit SHA in results
        # Match full SHA (40 chars) or abbreviated (7+ chars)
        sha_pattern = r'\b[a-f0-9]{7,40}\b'
        found_shas = re.findall(sha_pattern, results_content.lower())

        if not found_shas:
            feedback_parts.append("❌ No commit SHA found in BISECT_RESULTS.md")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + "\n\n💡 Hint: Include the bad commit's SHA in your results"
            }

        feedback_parts.append(f"✓ Found commit SHA in results: {found_shas[0][:12]}...")
        score += 15

        # Check 3: Verify it's the correct bad commit
        user_identified_commit = found_shas[0]
        metadata['user_sha'] = user_identified_commit
        metadata['actual_sha'] = actual_bad_commit

        correct_commit = False
        if actual_bad_commit:
            # Check if SHAs match (handle abbreviated vs full)
            actual_lower = actual_bad_commit.lower()
            user_lower = user_identified_commit.lower()

            if actual_lower.startswith(user_lower) or user_lower.startswith(actual_lower[:len(user_lower)]):
                feedback_parts.append("✅ Correctly identified the bad commit!")
                score += 30
                correct_commit = True
                metadata['correct_commit'] = True
            else:
                feedback_parts.append(f"❌ Identified commit {user_identified_commit[:8]} but expected {actual_bad_commit[:8]}")
                feedback_parts.append("   The commit you identified is not the one that introduced the bug")
                metadata['correct_commit'] = False
        else:
            # Can't verify - give partial credit
            feedback_parts.append("⚠️  Could not verify which commit is correct (missing reference)")
            score += 15  # Partial credit
            metadata['correct_commit'] = None

        # Check 4: Results include commit message
        message_keywords = ['refactor', 'clean up', 'message', 'commit message']
        has_message_info = any(keyword in results_content.lower() for keyword in message_keywords)

        if has_message_info:
            feedback_parts.append("✓ Results include commit message information")
            score += 10
        else:
            feedback_parts.append("⚠️  Results missing commit message")

        # Check 5: Results include files changed
        file_keywords = ['payment.js', 'file', 'changed', 'modified']
        has_file_info = any(keyword in results_content.lower() for keyword in file_keywords)

        if has_file_info:
            feedback_parts.append("✓ Results include files changed")
            score += 10
        else:
            feedback_parts.append("⚠️  Results missing files changed information")

        # Check 6: Results include analysis/hypothesis
        # Check for substantial content (more than just copy-paste of git output)
        analysis_keywords = ['bug', 'broke', 'breaks', 'issue', 'problem', 'clear', 'hypothesis', 'because', 'cause']
        has_analysis = any(keyword in results_content.lower() for keyword in analysis_keywords)

        if has_analysis and len(results_content) > 150:
            feedback_parts.append("✓ Results include analysis/hypothesis")
            score += 10
        else:
            feedback_parts.append("⚠️  Results missing detailed analysis or hypothesis")

        # Check 7: Git bisect was cleaned up
        bisect_cleaned = False
        if os.path.exists(bisect_status_file):
            with open(bisect_status_file, 'r') as f:
                status_content = f.read().strip()

            if 'BISECT_COMPLETED' in status_content:
                feedback_parts.append("✓ Git bisect properly finished (git bisect reset was run)")
                score += 10
                bisect_cleaned = True
            else:
                feedback_parts.append("⚠️  Git bisect still active - should run 'git bisect reset'")
                metadata['bisect_active'] = True
        else:
            # Assume cleaned if file doesn't exist
            bisect_cleaned = True

        # Calculate final result
        # Minimum passing criteria: correct commit identified + documentation present
        min_score_for_pass = 70
        passed = score >= min_score_for_pass and correct_commit

        feedback = "\n".join(feedback_parts)

        if passed:
            feedback += "\n\n🎉 Success! You correctly used git bisect to identify the regression and documented your findings."
        elif correct_commit:
            feedback += "\n\n⚠️  You found the correct commit, but documentation is incomplete."
        else:
            feedback += "\n\n❌ Task incomplete. Make sure you:"
            feedback += "\n   1. Use git bisect to find the bad commit"
            feedback += "\n   2. Document the SHA, message, files, and analysis in BISECT_RESULTS.md"
            feedback += "\n   3. Run 'git bisect reset' when done"

        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback,
            "metadata": metadata
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
