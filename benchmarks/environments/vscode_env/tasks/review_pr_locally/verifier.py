#!/usr/bin/env python3
"""
Verifier for review_pr_locally@1 task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that the agent successfully reviewed the PR locally.
    
    Success criteria:
    1. Checked out the correct branch (fix/sanitize-user-input) - 25 points
    2. Created pr_review_notes.txt - 20 points
    3. Notes mention branch name - 15 points
    4. Notes mention key changed files (validator.py) - 20 points
    5. Notes mention test changes - 15 points
    6. Notes describe the fix (bonus) - 5 points
    
    Pass threshold: 80/100
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='review_pr_verify_')
    
    try:
        score = 0.0
        max_score = 100.0
        feedback_parts = []
        metadata = {}
        
        # Copy exported files from /tmp
        current_branch_file = os.path.join(temp_dir, "current_branch.txt")
        review_notes_file = os.path.join(temp_dir, "pr_review_notes.txt")
        
        try:
            copy_from_env("/tmp/current_branch.txt", current_branch_file)
        except Exception as e:
            logger.warning(f"Failed to copy current_branch.txt: {e}")
            
        try:
            copy_from_env("/tmp/pr_review_notes.txt", review_notes_file)
        except Exception as e:
            logger.warning(f"Failed to copy pr_review_notes.txt: {e}")
        
        # Check 1: Was correct branch checked out? (25 points)
        if os.path.exists(current_branch_file):
            current_branch = read_file_content(current_branch_file).strip()
            metadata['current_branch'] = current_branch
            
            if current_branch == "fix/sanitize-user-input":
                score += 25
                feedback_parts.append("✅ Correctly checked out PR branch 'fix/sanitize-user-input'")
            else:
                feedback_parts.append(f"❌ Wrong branch: '{current_branch}' (expected 'fix/sanitize-user-input')")
        else:
            feedback_parts.append("❌ Could not determine current branch")
        
        # Check 2: Does pr_review_notes.txt exist? (20 points)
        if not os.path.exists(review_notes_file) or os.path.getsize(review_notes_file) == 0:
            feedback_parts.append("❌ CRITICAL: pr_review_notes.txt not found or empty")
            return {
                "passed": False,
                "score": int(score),
                "feedback": "\n".join(feedback_parts)
            }
        
        score += 20
        feedback_parts.append("✅ Created pr_review_notes.txt")
        
        # Read review notes
        review_notes = read_file_content(review_notes_file)
        review_notes_lower = review_notes.lower()
        metadata['review_notes_length'] = len(review_notes)
        
        if len(review_notes) < 50:
            feedback_parts.append("❌ Review notes too short (< 50 chars)")
            return {
                "passed": False,
                "score": int(score),
                "feedback": "\n".join(feedback_parts)
            }
        
        # Check 3: Does it mention the branch name? (15 points)
        if "fix/sanitize-user-input" in review_notes or "fix/sanitize" in review_notes_lower:
            score += 15
            feedback_parts.append("✅ Review notes mention the branch name")
        else:
            feedback_parts.append("❌ Review notes should mention branch 'fix/sanitize-user-input'")
        
        # Check 4: Does it mention validator.py? (20 points)
        validator_mentioned = (
            "validator.py" in review_notes_lower or 
            "validator" in review_notes_lower or
            "src/auth/validator" in review_notes_lower
        )
        if validator_mentioned:
            score += 20
            feedback_parts.append("✅ Review notes identify validator.py as changed file")
        else:
            feedback_parts.append("❌ Review notes should mention validator.py (key modified file)")
        
        # Check 5: Does it mention tests? (15 points)
        test_keywords = ["test", "test_validator", "tests", "testing"]
        if any(keyword in review_notes_lower for keyword in test_keywords):
            score += 15
            feedback_parts.append("✅ Review notes mention test changes")
        else:
            feedback_parts.append("❌ Review notes should mention test file changes")
        
        # Check 6: Does it describe what the fix does? (5 points bonus)
        fix_keywords = [
            "sanitiz", "escape", "html", "xss", "security", 
            "input", "injection", "control char", "vulnerability"
        ]
        if any(keyword in review_notes_lower for keyword in fix_keywords):
            score += 5
            feedback_parts.append("✅ BONUS: Review notes describe the nature of the fix")
        
        # Success threshold: 80/100
        success = score >= 80
        
        # Build final feedback
        final_feedback = "\n".join(feedback_parts)
        final_feedback += f"\n\n📊 Final Score: {int(score)}/{int(max_score)}"
        
        if success:
            final_feedback += "\n✅ Task completed successfully - PR review documented!"
        else:
            final_feedback += f"\n❌ Task incomplete (need {80-int(score)} more points)"
            final_feedback += "\nEnsure: correct branch checkout + review notes with branch name, files, and test mention"
        
        return {
            "passed": success,
            "score": int(score),
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
        cleanup_verification_temp(temp_dir)
