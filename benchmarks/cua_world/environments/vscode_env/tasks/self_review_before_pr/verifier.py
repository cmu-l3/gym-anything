#!/usr/bin/env python3
"""
Verifier for Self Review Before PR task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_self_review(traj, env_info, task_info):
    """
    Verify that the developer successfully self-reviewed and cleaned up code.
    
    Checks:
    1. Debug print statement removed from auth/login.py
    2. TODO comment removed or improved in auth/user.py
    3. Unused pdb import removed from utils/helpers.py
    4. Debug test file deleted or unstaged
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='self_review_verify_')
    
    try:
        # Copy exported files
        results_base = "/tmp/self_review_results"
        
        # Create local temp structure
        local_files_dir = os.path.join(temp_dir, "files")
        os.makedirs(local_files_dir, exist_ok=True)
        
        # Copy files
        files_to_check = {
            'login.py': f"{results_base}/files/login.py",
            'user.py': f"{results_base}/files/user.py",
            'helpers.py': f"{results_base}/files/helpers.py",
            'test_debug_exists.txt': f"{results_base}/test_debug_exists.txt",
            'git_status.txt': f"{results_base}/git_status.txt"
        }
        
        for local_name, container_path in files_to_check.items():
            local_path = os.path.join(temp_dir, local_name)
            try:
                copy_from_env(container_path, local_path)
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
        
        issues_fixed = []
        issues_remaining = []
        score = 0.0
        max_score = 4.0
        
        # Check 1: Debug print statement removed from auth/login.py
        login_file = os.path.join(temp_dir, "login.py")
        if os.path.exists(login_file) and os.path.getsize(login_file) > 0:
            with open(login_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Check for debug print statement
            if 'print("DEBUG:' in content or "print('DEBUG:" in content or 'print("DEBUG' in content:
                issues_remaining.append("Debug print statement still in auth/login.py")
            else:
                issues_fixed.append("Debug print statement removed from auth/login.py")
                score += 1.0
        else:
            issues_remaining.append("auth/login.py not found or empty")
        
        # Check 2: TODO comment removed or improved in auth/user.py
        user_file = os.path.join(temp_dir, "user.py")
        if os.path.exists(user_file) and os.path.getsize(user_file) > 0:
            with open(user_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Check if the specific vague TODO is gone
            if "TODO: This is hacky, refactor later" in content:
                issues_remaining.append("Vague TODO comment still in auth/user.py")
            else:
                # Either removed entirely or improved
                issues_fixed.append("TODO comment removed or improved in auth/user.py")
                score += 1.0
        else:
            issues_remaining.append("auth/user.py not found or empty")
        
        # Check 3: Unused pdb import removed from utils/helpers.py
        helpers_file = os.path.join(temp_dir, "helpers.py")
        if os.path.exists(helpers_file) and os.path.getsize(helpers_file) > 0:
            with open(helpers_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Check for standalone pdb import at module level
            if re.search(r'^\s*import\s+pdb\s*$', content, re.MULTILINE):
                issues_remaining.append("Unused 'import pdb' still in utils/helpers.py")
            else:
                issues_fixed.append("Unused pdb import removed from utils/helpers.py")
                score += 1.0
        else:
            issues_remaining.append("utils/helpers.py not found or empty")
        
        # Check 4: Debug test file removed or unstaged
        test_debug_status_file = os.path.join(temp_dir, "test_debug_exists.txt")
        git_status_file = os.path.join(temp_dir, "git_status.txt")
        
        debug_file_handled = False
        
        # Check if file is deleted
        if os.path.exists(test_debug_status_file):
            with open(test_debug_status_file, 'r') as f:
                status = f.read().strip()
            
            if status == "deleted":
                debug_file_handled = True
                issues_fixed.append("Debug test file (test_debug.py) deleted")
                score += 1.0
            else:
                # File still exists, check if it's unstaged
                if os.path.exists(git_status_file):
                    with open(git_status_file, 'r') as f:
                        git_status = f.read()
                    
                    # Check if test_debug.py is in the staged area
                    # If it's marked as untracked (??) or not present, it's not staged
                    lines_with_debug = [line for line in git_status.split('\n') if 'test_debug.py' in line]
                    
                    if not lines_with_debug:
                        # Not in git status at all - good
                        debug_file_handled = True
                        issues_fixed.append("Debug test file removed from staging")
                        score += 0.8
                    else:
                        # Check if it's untracked
                        untracked = any(line.startswith('??') for line in lines_with_debug)
                        if untracked:
                            debug_file_handled = True
                            issues_fixed.append("Debug test file unstaged (untracked)")
                            score += 0.6
                        else:
                            # Still staged
                            issues_remaining.append("Debug test file (test_debug.py) still staged for commit")
                else:
                    issues_remaining.append("Debug test file still exists (git status unavailable)")
        else:
            # Could not determine status
            issues_remaining.append("Could not verify debug test file status")
        
        # Calculate final reward
        reward = score / max_score
        success = reward >= 0.75  # Need to fix at least 3 out of 4 issues
        
        # Generate feedback
        feedback_parts = []
        if issues_fixed:
            feedback_parts.append("✅ Fixed: " + " | ".join(issues_fixed))
        if issues_remaining:
            feedback_parts.append("❌ Remaining: " + " | ".join(issues_remaining))
        
        feedback = " || ".join(feedback_parts) if feedback_parts else "No feedback available"
        
        # Add score info
        feedback = f"Score: {score:.1f}/{max_score} || {feedback}"
        
        return {
            "passed": success,
            "score": int(reward * 100),
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
