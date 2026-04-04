#!/usr/bin/env python3
"""
Verifier for setup_precommit_hooks@1 task
"""

import sys
import os
import logging
import tempfile
import shutil
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_precommit_setup(traj, env_info, task_info):
    """
    Verify that pre-commit hooks are properly configured.
    
    Checks:
    1. .pre-commit-config.yaml exists and is valid YAML
    2. All four required hooks are configured (black, flake8, detect-secrets, check-added-large-files)
    3. Git hooks installed (.git/hooks/pre-commit exists and is executable)
    4. pre-commit dependency documented in requirements file
    5. Configuration committed to repository
    6. Evidence of testing (git history mentions pre-commit/hooks OR code was formatted)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='precommit_verify_')

    try:
        # Copy exported files
        config_local = os.path.join(temp_dir, "precommit_config.yaml")
        hook_status_local = os.path.join(temp_dir, "hook_status.txt")
        req_local = os.path.join(temp_dir, "requirements.txt")
        req_dev_local = os.path.join(temp_dir, "requirements-dev.txt")
        git_log_local = os.path.join(temp_dir, "git_log.txt")
        config_commits_local = os.path.join(temp_dir, "config_commits.txt")
        app_py_local = os.path.join(temp_dir, "app_py_final.txt")

        # Copy all files
        files_to_copy = [
            ("/tmp/precommit_config.yaml", config_local),
            ("/tmp/hook_status.txt", hook_status_local),
            ("/tmp/requirements.txt", req_local),
            ("/tmp/requirements-dev.txt", req_dev_local),
            ("/tmp/git_log.txt", git_log_local),
            ("/tmp/config_commits.txt", config_commits_local),
            ("/tmp/app_py_final.txt", app_py_local),
        ]

        for src, dst in files_to_copy:
            try:
                copy_from_env(src, dst)
            except Exception as e:
                logger.warning(f"Failed to copy {src}: {e}")

        checks_passed = 0
        total_checks = 6
        feedback_parts = []

        # Check 1: Config file exists and is valid YAML
        config_valid = False
        config_data = {}
        if os.path.exists(config_local) and os.path.getsize(config_local) > 0:
            with open(config_local, 'r') as f:
                content = f.read()
                if content.strip() != "FILE_NOT_FOUND":
                    try:
                        config_data = yaml.safe_load(content)
                        if isinstance(config_data, dict) and 'repos' in config_data:
                            config_valid = True
                            checks_passed += 1
                            feedback_parts.append("✅ .pre-commit-config.yaml exists and is valid YAML")
                        else:
                            feedback_parts.append("❌ Config file exists but missing 'repos' key")
                    except yaml.YAMLError as e:
                        feedback_parts.append(f"❌ Config file has invalid YAML: {str(e)[:50]}")
                else:
                    feedback_parts.append("❌ .pre-commit-config.yaml not found in repository")
        else:
            feedback_parts.append("❌ .pre-commit-config.yaml not found")

        # Check 2: Required hooks are configured
        if config_valid and config_data:
            hook_ids = []
            for repo in config_data.get('repos', []):
                for hook in repo.get('hooks', []):
                    hook_id = hook.get('id', '')
                    if hook_id:
                        hook_ids.append(hook_id.lower())

            required_hooks = {'black', 'flake8', 'detect-secrets', 'check-added-large-files'}
            found_hooks = set()
            
            for hook_id in hook_ids:
                for required in required_hooks:
                    if required in hook_id:
                        found_hooks.add(required)

            missing_hooks = required_hooks - found_hooks

            if len(missing_hooks) == 0:
                checks_passed += 1
                feedback_parts.append(f"✅ All required hooks configured: {', '.join(sorted(found_hooks))}")
            else:
                feedback_parts.append(f"❌ Missing required hooks: {', '.join(sorted(missing_hooks))}")
        else:
            feedback_parts.append("❌ Cannot check hooks (config invalid)")

        # Check 3: Git hooks installed
        hook_installed = False
        if os.path.exists(hook_status_local):
            with open(hook_status_local, 'r') as f:
                content = f.read()
                if "INSTALLED" in content or "pre-commit" in content.lower():
                    hook_installed = True
                    checks_passed += 1
                    feedback_parts.append("✅ Git hooks installed in .git/hooks/pre-commit")
                else:
                    feedback_parts.append("❌ Git hooks not installed (run 'pre-commit install')")
        else:
            feedback_parts.append("❌ Cannot verify hook installation status")

        # Check 4: pre-commit in requirements
        dependency_found = False
        for req_file in [req_local, req_dev_local]:
            if os.path.exists(req_file) and os.path.getsize(req_file) > 0:
                with open(req_file, 'r') as f:
                    content = f.read().lower()
                    if content.strip() != "no_file" and 'pre-commit' in content:
                        dependency_found = True
                        break

        if dependency_found:
            checks_passed += 1
            feedback_parts.append("✅ pre-commit dependency documented in requirements")
        else:
            feedback_parts.append("❌ pre-commit not added to requirements.txt or requirements-dev.txt")

        # Check 5: Configuration committed to git
        config_committed = False
        if os.path.exists(config_commits_local) and os.path.getsize(config_commits_local) > 0:
            with open(config_commits_local, 'r') as f:
                content = f.read().strip()
                if content and content != "":
                    config_committed = True
                    checks_passed += 1
                    feedback_parts.append("✅ Configuration committed to repository")
                else:
                    feedback_parts.append("❌ Configuration not committed to git")
        else:
            feedback_parts.append("❌ Cannot verify if configuration was committed")

        # Check 6: Evidence of testing
        testing_evidence = False
        
        # Method 1: Check git log for hook-related commit messages
        if os.path.exists(git_log_local):
            with open(git_log_local, 'r') as f:
                log_content = f.read().lower()
                if any(keyword in log_content for keyword in ['pre-commit', 'hook', 'black', 'format', 'lint']):
                    testing_evidence = True

        # Method 2: Check if code was formatted (app.py should have proper imports)
        if not testing_evidence and os.path.exists(app_py_local):
            with open(app_py_local, 'r') as f:
                content = f.read()
                # Black formats imports: "from flask import Flask, jsonify" not "Flask,jsonify"
                if "Flask, jsonify" in content:
                    testing_evidence = True

        if testing_evidence:
            checks_passed += 1
            feedback_parts.append("✅ Evidence of hook testing found")
        else:
            feedback_parts.append("❌ No evidence that hooks were tested (run 'pre-commit run --all-files')")

        # Calculate score and result
        score = int((checks_passed / total_checks) * 100)
        
        # Full pass requires all checks (or almost all)
        if checks_passed == total_checks:
            passed = True
            feedback = f"SUCCESS: All {total_checks} checks passed!\n" + "\n".join(feedback_parts)
        elif checks_passed >= total_checks - 1:
            passed = False
            score = 85
            feedback = f"NEARLY COMPLETE: {checks_passed}/{total_checks} checks passed\n" + "\n".join(feedback_parts)
        elif checks_passed >= 3:
            passed = False
            score = 50
            feedback = f"PARTIAL: Setup partially complete ({checks_passed}/{total_checks} checks)\n" + "\n".join(feedback_parts)
        else:
            passed = False
            feedback = f"FAILED: Only {checks_passed}/{total_checks} checks passed\n" + "\n".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
