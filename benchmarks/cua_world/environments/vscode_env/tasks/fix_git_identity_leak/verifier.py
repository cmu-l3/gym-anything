#!/usr/bin/env python3
"""
Verifier for Fix Git Identity Leak task
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


def verify_git_identity_fix(traj, env_info, task_info):
    """
    Verify that git identity leak was fixed and conditional config set up.
    
    Checks:
    1. Most recent commit in personal repo has correct author (Personal Dev <personal.dev@example.com>)
    2. ~/.gitconfig contains includeIf directives for work and personal directories
    3. Identity config files exist with correct content
    4. Config resolution works correctly in each directory
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='git_identity_verify_')
    
    try:
        # Copy exported files
        local_commit = os.path.join(temp_dir, "personal_commit.txt")
        local_gitconfig = os.path.join(temp_dir, "gitconfig.txt")
        local_work_config = os.path.join(temp_dir, "gitconfig-work.txt")
        local_personal_config = os.path.join(temp_dir, "gitconfig-personal.txt")
        local_work_test = os.path.join(temp_dir, "work_config_test.txt")
        local_personal_test = os.path.join(temp_dir, "personal_config_test.txt")
        
        try:
            copy_from_env("/tmp/personal_commit.txt", local_commit)
            copy_from_env("/tmp/gitconfig.txt", local_gitconfig)
            copy_from_env("/tmp/gitconfig-work.txt", local_work_config)
            copy_from_env("/tmp/gitconfig-personal.txt", local_personal_config)
            copy_from_env("/tmp/work_config_test.txt", local_work_test)
            copy_from_env("/tmp/personal_config_test.txt", local_personal_test)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy verification files: {str(e)}"}
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Check commit author is fixed
        commit_fixed = False
        if os.path.exists(local_commit):
            with open(local_commit, 'r') as f:
                commit_line = f.read().strip()
            
            if commit_line and commit_line != "No commits" and commit_line != "No git repository":
                parts = commit_line.split('|')
                if len(parts) >= 3:
                    commit_hash = parts[0]
                    author_name = parts[1].strip()
                    author_email = parts[2].strip()
                    
                    # Check if author is correct
                    if author_name == "Personal Dev" and author_email == "personal.dev@example.com":
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Commit author fixed: {author_name} <{author_email}>")
                        commit_fixed = True
                    else:
                        feedback_parts.append(f"❌ Commit author incorrect: {author_name} <{author_email}> (expected: Personal Dev <personal.dev@example.com>)")
                else:
                    feedback_parts.append(f"❌ Could not parse commit info: {commit_line}")
            else:
                feedback_parts.append("❌ No commit found in personal repository")
        else:
            feedback_parts.append("❌ Commit info file not found")
        
        # Criterion 2: Check gitconfig has includeIf directives
        has_conditional_config = False
        if os.path.exists(local_gitconfig):
            with open(local_gitconfig, 'r') as f:
                gitconfig_content = f.read()
            
            # Check for includeIf directives (flexible path matching)
            has_work_include = bool(re.search(r'\[includeIf\s+"gitdir:.*workspace/work/?.*"\]', gitconfig_content))
            has_personal_include = bool(re.search(r'\[includeIf\s+"gitdir:.*workspace/personal/?.*"\]', gitconfig_content))
            
            # Also check for path directives
            has_work_path = 'gitconfig-work' in gitconfig_content
            has_personal_path = 'gitconfig-personal' in gitconfig_content
            
            if (has_work_include or 'gitdir:~/workspace/work' in gitconfig_content or 'gitdir:/home/ga/workspace/work' in gitconfig_content) and \
               (has_personal_include or 'gitdir:~/workspace/personal' in gitconfig_content or 'gitdir:/home/ga/workspace/personal' in gitconfig_content) and \
               has_work_path and has_personal_path:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional git configuration found in ~/.gitconfig")
                has_conditional_config = True
            else:
                feedback_parts.append("❌ Conditional includeIf directives not properly configured in ~/.gitconfig")
        else:
            feedback_parts.append("❌ ~/.gitconfig file not found")
        
        # Criterion 3: Check identity files exist and have correct content
        identity_files_valid = False
        work_valid = False
        personal_valid = False
        
        # Check work identity file
        if os.path.exists(local_work_config):
            with open(local_work_config, 'r') as f:
                work_content = f.read()
            
            has_work_name = 'Corporate Dev' in work_content
            has_work_email = 'dev@megacorp.com' in work_content
            
            if has_work_name and has_work_email:
                work_valid = True
        
        # Check personal identity file
        if os.path.exists(local_personal_config):
            with open(local_personal_config, 'r') as f:
                personal_content = f.read()
            
            has_personal_name = 'Personal Dev' in personal_content
            has_personal_email = 'personal.dev@example.com' in personal_content
            
            if has_personal_name and has_personal_email:
                personal_valid = True
        
        if work_valid and personal_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Both work and personal identity files configured correctly")
            identity_files_valid = True
        else:
            missing = []
            if not work_valid:
                missing.append("~/.gitconfig-work")
            if not personal_valid:
                missing.append("~/.gitconfig-personal")
            feedback_parts.append(f"❌ Identity files missing or incorrect: {', '.join(missing)}")
        
        # Criterion 4: Verify config resolution works in practice
        config_resolution_works = False
        if os.path.exists(local_work_test) and os.path.exists(local_personal_test):
            with open(local_work_test, 'r') as f:
                work_test = f.read().strip()
            with open(local_personal_test, 'r') as f:
                personal_test = f.read().strip()
            
            # Parse test results
            work_parts = work_test.split('|')
            personal_parts = personal_test.split('|')
            
            work_resolves_correctly = (
                len(work_parts) == 2 and
                work_parts[0].strip() == "Corporate Dev" and
                work_parts[1].strip() == "dev@megacorp.com"
            )
            
            personal_resolves_correctly = (
                len(personal_parts) == 2 and
                personal_parts[0].strip() == "Personal Dev" and
                personal_parts[1].strip() == "personal.dev@example.com"
            )
            
            if work_resolves_correctly and personal_resolves_correctly:
                criteria_passed += 1
                feedback_parts.append("✅ Configuration correctly resolves in both work and personal directories")
                config_resolution_works = True
            else:
                feedback_parts.append("⚠️ Configuration files exist but may not resolve correctly")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "commit_fixed": commit_fixed,
                "conditional_config": has_conditional_config,
                "identity_files": identity_files_valid,
                "config_resolution": config_resolution_works
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
