#!/usr/bin/env python3
"""
Verifier for Salvage Interrupted Work task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_salvage_work(traj, env_info, task_info):
    """
    Verify that workspace was properly cleaned up with changes separated.
    
    Checks:
    1. Currently on main branch
    2. Workspace is clean (no uncommitted changes)
    3. Branch feature/jwt-authentication exists
    4. Bug fix commit on main with correct message and files
    5. Auth WIP commit on feature branch with correct message and files
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='salvage_verify_')

    try:
        # Copy all exported git data
        files_to_copy = {
            'current_branch': '/tmp/salvage_current_branch.txt',
            'git_status': '/tmp/salvage_git_status.txt',
            'git_branches': '/tmp/salvage_git_branches.txt',
            'git_log_main': '/tmp/salvage_git_log_main.txt',
            'git_log_feature': '/tmp/salvage_git_log_feature.txt',
            'main_commit_files': '/tmp/salvage_main_commit_files.txt',
            'feature_diff_files': '/tmp/salvage_feature_diff_files.txt',
            'main_commit_count': '/tmp/salvage_main_commit_count.txt',
            'feature_commit_count': '/tmp/salvage_feature_commit_count.txt',
        }

        local_files = {}
        for key, remote_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, f"{key}.txt")
            try:
                copy_from_env(remote_path, local_path)
                local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {remote_path}: {e}")
                # Create empty file as fallback
                with open(local_path, 'w') as f:
                    f.write("")
                local_files[key] = local_path

        score = 0.0
        feedback_parts = []

        # Check 1: Verify we're on main branch (15 points)
        current_branch = ""
        if os.path.exists(local_files['current_branch']):
            with open(local_files['current_branch'], 'r') as f:
                current_branch = f.read().strip()

        if current_branch == 'main':
            feedback_parts.append("✅ Currently on 'main' branch")
            score += 0.15
        else:
            feedback_parts.append(f"❌ Currently on '{current_branch}' instead of 'main'")

        # Check 2: Verify git status is clean (15 points)
        git_status_clean = False
        if os.path.exists(local_files['git_status']):
            with open(local_files['git_status'], 'r') as f:
                status_content = f.read().strip()

            if not status_content:
                feedback_parts.append("✅ Workspace is clean (no uncommitted changes)")
                score += 0.15
                git_status_clean = True
            else:
                uncommitted_count = len(status_content.split('\n'))
                feedback_parts.append(f"❌ Workspace has {uncommitted_count} uncommitted changes")

        # Check 3: Verify feature branch exists (15 points)
        has_feature_branch = False
        if os.path.exists(local_files['git_branches']):
            with open(local_files['git_branches'], 'r') as f:
                branches_content = f.read()

            if 'feature/jwt-authentication' in branches_content:
                feedback_parts.append("✅ Branch 'feature/jwt-authentication' exists")
                score += 0.15
                has_feature_branch = True
            else:
                feedback_parts.append("❌ Branch 'feature/jwt-authentication' not found")

        # Check 4: Verify bug fix commit on main (20 points for message + 15 for files)
        main_commits = []
        if os.path.exists(local_files['git_log_main']):
            with open(local_files['git_log_main'], 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and '|' in line:
                        parts = line.split('|', 3)
                        if len(parts) >= 2:
                            main_commits.append({
                                'hash': parts[0],
                                'message': parts[1]
                            })

        # Check commit count (should be at least 2: initial + bug fix)
        main_commit_count = 0
        if os.path.exists(local_files['main_commit_count']):
            with open(local_files['main_commit_count'], 'r') as f:
                try:
                    main_commit_count = int(f.read().strip())
                except:
                    main_commit_count = len(main_commits)

        has_bugfix_commit = False
        if len(main_commits) >= 2:
            # Most recent commit (first in log) should be the bug fix
            recent_commit = main_commits[0]
            message = recent_commit['message'].lower()
            
            # Check for keywords in commit message
            bugfix_keywords = ['null safety', 'fix', 'crash', 'prevent', 'null check']
            if any(keyword in message for keyword in bugfix_keywords):
                feedback_parts.append(f"✅ Bug fix commit found: '{recent_commit['message']}'")
                score += 0.20
                has_bugfix_commit = True

                # Check 4a: Verify bug fix commit contains correct files (15 points)
                if os.path.exists(local_files['main_commit_files']):
                    with open(local_files['main_commit_files'], 'r') as f:
                        changed_files = [line.strip() for line in f if line.strip()]

                    expected_files = ['users.js', 'products.js', 'logger.js']
                    auth_files = ['jwt.js', 'auth.test.js']

                    has_expected = all(any(exp in cf for cf in changed_files) for exp in expected_files)
                    has_auth = any(any(auth in cf for auth in auth_files) for cf in changed_files)

                    if has_expected and not has_auth:
                        feedback_parts.append("✅ Bug fix commit includes correct files only")
                        score += 0.15
                    elif has_expected:
                        feedback_parts.append(f"⚠️ Bug fix commit includes auth files (should be separate)")
                        score += 0.05
                    else:
                        feedback_parts.append(f"❌ Bug fix commit missing expected files")
            else:
                feedback_parts.append(f"❌ Latest commit message doesn't match bug fix: '{recent_commit['message']}'")
        else:
            feedback_parts.append(f"❌ Not enough commits on main (found {len(main_commits)}, expected at least 2)")

        # Check 5: Verify auth commit on feature branch (20 points for message + 15 for files)
        if has_feature_branch:
            feature_commits = []
            if os.path.exists(local_files['git_log_feature']):
                with open(local_files['git_log_feature'], 'r') as f:
                    content = f.read()
                    if 'Branch does not exist' not in content:
                        for line in content.split('\n'):
                            line = line.strip()
                            if line and '|' in line:
                                parts = line.split('|', 3)
                                if len(parts) >= 2:
                                    feature_commits.append({
                                        'hash': parts[0],
                                        'message': parts[1]
                                    })

            # Check feature commit count
            feature_commit_count = 0
            if os.path.exists(local_files['feature_commit_count']):
                with open(local_files['feature_commit_count'], 'r') as f:
                    try:
                        feature_commit_count = int(f.read().strip())
                    except:
                        feature_commit_count = len(feature_commits)

            # Feature branch should have at least one more commit than main
            if feature_commit_count > main_commit_count:
                # Find the commit unique to feature branch
                has_auth_commit = False
                for commit in feature_commits:
                    message = commit['message'].lower()
                    auth_keywords = ['wip', 'auth', 'jwt', 'incomplete', 'work in progress']
                    
                    if any(keyword in message for keyword in auth_keywords):
                        feedback_parts.append(f"✅ Auth WIP commit found: '{commit['message']}'")
                        score += 0.20
                        has_auth_commit = True
                        break

                if not has_auth_commit:
                    feedback_parts.append("❌ No WIP auth commit found on feature branch")

                # Check 5a: Verify auth commit contains correct files (15 points)
                if os.path.exists(local_files['feature_diff_files']):
                    with open(local_files['feature_diff_files'], 'r') as f:
                        diff_files = [line.strip() for line in f if line.strip()]

                    expected_auth_files = ['jwt.js', 'auth.js', 'auth.test.js']
                    bug_fix_files = ['users.js', 'products.js', 'logger.js']

                    has_auth_files = any(any(exp in df for df in diff_files) for exp in expected_auth_files)
                    has_bug_files = any(any(bug in df for df in diff_files) for bug in bug_fix_files)

                    if has_auth_files and not has_bug_files:
                        feedback_parts.append("✅ Feature branch includes auth files only")
                        score += 0.15
                    elif has_auth_files:
                        feedback_parts.append("⚠️ Feature branch includes unexpected files")
                        score += 0.05
                    else:
                        feedback_parts.append("❌ Feature branch missing auth files")
            else:
                feedback_parts.append(f"❌ Feature branch has no additional commits (main: {main_commit_count}, feature: {feature_commit_count})")

        # Final assessment
        feedback = " | ".join(feedback_parts)
        passed = score >= 0.75

        if passed:
            feedback += f"\n\n🎉 Task completed successfully! (Score: {score:.2f})"
        else:
            feedback += f"\n\n❌ Task incomplete (Score: {score:.2f}/1.00, need ≥0.75)"

        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
