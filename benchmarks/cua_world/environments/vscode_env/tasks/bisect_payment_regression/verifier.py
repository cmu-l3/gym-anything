#!/usr/bin/env python3
"""
Verifier for Git Bisect Payment Regression task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bisect_payment_regression(traj, env_info, task_info):
    """
    Verify that Git bisect correctly identified the regression commit.
    
    Checks:
    1. Bisect result file exists and has content
    2. Bisect log contains proper good/bad markings (sufficient iterations)
    3. Correct culprit commit identified (contains "Refactor Visa validation")
    4. Git bisect session was properly terminated (not still in bisect mode)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='bisect_verify_')

    try:
        # Copy exported files
        export_dir = "/tmp/bisect_task_results"
        
        bisect_result_path = os.path.join(export_dir, "bisect_result.txt")
        git_log_path = os.path.join(export_dir, "git_log.txt")
        bisect_warning_path = os.path.join(export_dir, "bisect_warning.txt")
        culprit_commit_path = os.path.join(export_dir, "culprit_commit.txt")
        
        local_bisect = os.path.join(temp_dir, "bisect_result.txt")
        local_git_log = os.path.join(temp_dir, "git_log.txt")
        local_warning = os.path.join(temp_dir, "bisect_warning.txt")
        local_culprit = os.path.join(temp_dir, "culprit_commit.txt")
        
        # Copy files
        try:
            copy_from_env(bisect_result_path, local_bisect)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy bisect result: {str(e)}"}
        
        try:
            copy_from_env(git_log_path, local_git_log)
        except:
            pass
        
        try:
            copy_from_env(bisect_warning_path, local_warning)
        except:
            pass
            
        try:
            copy_from_env(culprit_commit_path, local_culprit)
        except:
            pass

        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []

        # Check 1: Result file exists and has content (25 points)
        if not os.path.exists(local_bisect):
            return {"passed": False, "score": 0, "feedback": "❌ Bisect result file not found at /home/ga/workspace/bisect_result.txt"}
        
        bisect_log = read_file_content(local_bisect)
        
        if len(bisect_log.strip()) < 50:
            return {"passed": False, "score": 0, "feedback": "❌ Bisect result file is too short or empty. Expected full bisect log output from 'git bisect log'."}
        
        criteria_passed += 1
        feedback_parts.append("✅ Bisect result file exists with content")

        # Check 2: Git is not still in bisect mode (25 points)
        if os.path.exists(local_warning):
            warning_content = read_file_content(local_warning)
            if "still in bisect mode" in warning_content.lower():
                feedback_parts.append("❌ Repository is still in bisect mode. Must run 'git bisect reset' to finish.")
                return {"passed": False, "score": 25, "feedback": " | ".join(feedback_parts)}
        
        criteria_passed += 1
        feedback_parts.append("✅ Bisect session was properly terminated")

        # Check 3: Bisect log contains proper markings (25 points)
        good_count = bisect_log.count("git bisect good")
        bad_count = bisect_log.count("git bisect bad")
        
        # In a binary search through ~23 commits, expect at least 4-5 iterations
        if good_count < 3 or bad_count < 3:
            feedback_parts.append(f"❌ Insufficient bisect iterations. Found {good_count} good, {bad_count} bad markings. Expected at least 3 of each for proper bisect.")
            return {"passed": False, "score": 50, "feedback": " | ".join(feedback_parts)}
        
        criteria_passed += 1
        feedback_parts.append(f"✅ Bisect log shows {good_count} good and {bad_count} bad markings")

        # Check 4: Correct commit identified (25 points)
        culprit_commit_sha = None
        
        # Get the culprit commit from the exported file
        if os.path.exists(local_culprit):
            culprit_line = read_file_content(local_culprit).strip()
            if culprit_line and "Refactor Visa validation" in culprit_line:
                # Extract the SHA (first part before space)
                culprit_commit_sha = culprit_line.split()[0]
        
        if not culprit_commit_sha:
            # Fallback: search git log
            if os.path.exists(local_git_log):
                git_log_content = read_file_content(local_git_log)
                for line in git_log_content.split('\n'):
                    if "Refactor Visa validation" in line:
                        culprit_commit_sha = line.split()[0]
                        break
        
        if not culprit_commit_sha:
            feedback_parts.append("⚠️ Could not determine expected culprit commit from repository")
            # Still check if bisect found SOMETHING reasonable
            if "is the first bad commit" in bisect_log.lower() or "bisect found" in bisect_log.lower():
                criteria_passed += 1
                feedback_parts.append("✅ Bisect identified a commit as culprit")
            else:
                feedback_parts.append("❌ Bisect did not identify any commit as culprit")
        else:
            # Check if this commit SHA appears in bisect log
            # The bisect log should contain the culprit commit hash
            if culprit_commit_sha in bisect_log:
                criteria_passed += 1
                feedback_parts.append(f"✅ Correctly identified culprit commit: {culprit_commit_sha}")
            else:
                # Try partial match (sometimes Git uses abbreviated SHAs)
                found_partial = False
                for sha_len in range(7, len(culprit_commit_sha) + 1):
                    partial_sha = culprit_commit_sha[:sha_len]
                    if partial_sha in bisect_log:
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Correctly identified culprit commit: {partial_sha}")
                        found_partial = True
                        break
                
                if not found_partial:
                    feedback_parts.append(f"❌ Bisect did not identify the correct commit. Expected {culprit_commit_sha} ('Refactor Visa validation pattern') to appear in log.")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = (criteria_passed == total_criteria)

        if passed:
            feedback_parts.append("🎉 SUCCESS! Git bisect correctly found the regression.")
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
