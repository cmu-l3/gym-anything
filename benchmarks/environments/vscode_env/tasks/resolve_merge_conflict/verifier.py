#!/usr/bin/env python3
"""
Verifier for Merge Conflict Resolution task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_merge_conflict_resolution(traj, env_info, task_info):
    """
    Verify that merge conflicts were successfully resolved.

    Checks:
    1. Merge is completed (no MERGE_HEAD file)
    2. Working tree is clean (no unstaged/staged changes)
    3. Latest commit is a merge commit (has 2 parents)
    4. No conflict markers remain in files
    5. Files have valid Python syntax
    6. Expected content present (tax_rate parameter, correct config values)
    7. Both files were resolved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='merge_verify_')

    try:
        # Copy all exported data files
        files_to_copy = {
            'merge_state': '/tmp/merge_state.txt',
            'git_status': '/tmp/merge_git_status.txt',
            'git_log': '/tmp/merge_git_log.txt',
            'commit_parents': '/tmp/merge_commit_parents.txt',
            'utils_py': '/tmp/merge_utils_py.txt',
            'config_py': '/tmp/merge_config_py.txt',
        }

        local_files = {}
        for key, container_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, f"{key}.txt")
            try:
                copy_from_env(container_path, local_path)
                local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
                return {"passed": False, "score": 0, "feedback": f"Failed to copy {key}: {str(e)}"}

        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Criterion 1: Merge is completed (no MERGE_HEAD)
        merge_state = ""
        if os.path.exists(local_files['merge_state']):
            with open(local_files['merge_state'], 'r') as f:
                merge_state = f.read().strip()

        if merge_state == "MERGE_COMPLETED":
            criteria_passed += 1
            feedback_parts.append("✅ Merge completed (no active merge state)")
        elif merge_state == "MERGE_IN_PROGRESS":
            feedback_parts.append("❌ Merge not completed (MERGE_HEAD still exists)")
        else:
            feedback_parts.append(f"❌ Unexpected merge state: {merge_state}")

        # Criterion 2: Working tree is clean
        git_status_clean = False
        if os.path.exists(local_files['git_status']):
            with open(local_files['git_status'], 'r') as f:
                status_content = f.read().strip()

            if not status_content or status_content == "":
                criteria_passed += 1
                feedback_parts.append("✅ Working tree is clean")
                git_status_clean = True
            else:
                # Check if only untracked files (which is OK)
                lines = status_content.split('\n')
                all_untracked = all(line.startswith('??') for line in lines if line)
                if all_untracked:
                    criteria_passed += 1
                    feedback_parts.append("✅ Working tree clean (only untracked files)")
                    git_status_clean = True
                else:
                    feedback_parts.append(f"❌ Working tree has uncommitted changes: {status_content[:100]}")

        # Criterion 3: Latest commit is a merge commit (has 2 parents)
        is_merge_commit = False
        if os.path.exists(local_files['commit_parents']):
            with open(local_files['commit_parents'], 'r') as f:
                parents = f.read().strip().split()
                # Format: commit_hash parent1_hash parent2_hash
                if len(parents) == 3:
                    criteria_passed += 1
                    feedback_parts.append("✅ Latest commit is a merge commit (2 parents)")
                    is_merge_commit = True
                elif len(parents) == 2:
                    feedback_parts.append("❌ Latest commit is not a merge commit (only 1 parent)")
                else:
                    feedback_parts.append(f"❌ Unexpected commit parent structure: {len(parents)-1} parents")

        # Criterion 4: No conflict markers in files
        conflict_markers = ['<<<<<<<', '=======', '>>>>>>>']
        files_with_markers = []

        utils_content = ""
        config_content = ""

        if os.path.exists(local_files['utils_py']):
            with open(local_files['utils_py'], 'r') as f:
                utils_content = f.read()
                for marker in conflict_markers:
                    if marker in utils_content:
                        files_with_markers.append("utils.py")
                        break

        if os.path.exists(local_files['config_py']):
            with open(local_files['config_py'], 'r') as f:
                config_content = f.read()
                for marker in conflict_markers:
                    if marker in config_content:
                        files_with_markers.append("config.py")
                        break

        if not files_with_markers:
            criteria_passed += 1
            feedback_parts.append("✅ No conflict markers remain in files")
        else:
            feedback_parts.append(f"❌ Conflict markers found in: {', '.join(files_with_markers)}")

        # Criterion 5: Files have valid Python syntax
        syntax_valid = True
        syntax_errors = []

        # Check utils.py syntax
        if utils_content and utils_content != "FILE_NOT_FOUND":
            utils_temp = tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False)
            try:
                utils_temp.write(utils_content)
                utils_temp.close()
                
                import subprocess
                result = subprocess.run(
                    ['python3', '-m', 'py_compile', utils_temp.name],
                    capture_output=True,
                    text=True
                )
                if result.returncode != 0:
                    syntax_valid = False
                    syntax_errors.append("utils.py")
            except Exception as e:
                logger.warning(f"Failed to check utils.py syntax: {e}")
            finally:
                if os.path.exists(utils_temp.name):
                    os.unlink(utils_temp.name)

        # Check config.py syntax
        if config_content and config_content != "FILE_NOT_FOUND":
            config_temp = tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False)
            try:
                config_temp.write(config_content)
                config_temp.close()
                
                result = subprocess.run(
                    ['python3', '-m', 'py_compile', config_temp.name],
                    capture_output=True,
                    text=True
                )
                if result.returncode != 0:
                    syntax_valid = False
                    syntax_errors.append("config.py")
            except Exception as e:
                logger.warning(f"Failed to check config.py syntax: {e}")
            finally:
                if os.path.exists(config_temp.name):
                    os.unlink(config_temp.name)

        if syntax_valid and not syntax_errors:
            criteria_passed += 1
            feedback_parts.append("✅ All files have valid Python syntax")
        else:
            feedback_parts.append(f"❌ Syntax errors in: {', '.join(syntax_errors)}")

        # Criterion 6: Expected content present (correct resolution)
        correct_resolution = True
        resolution_issues = []

        # Check utils.py has tax_rate parameter (from incoming/main branch)
        if utils_content and utils_content != "FILE_NOT_FOUND":
            if 'tax_rate' in utils_content and 'def calculate_price(base, discount, tax_rate)' in utils_content:
                pass  # Good
            else:
                correct_resolution = False
                resolution_issues.append("utils.py missing tax_rate parameter")

        # Check config.py has correct values (from incoming/main branch)
        if config_content and config_content != "FILE_NOT_FOUND":
            if 'DEFAULT_TIMEOUT = 60' in config_content or 'DEFAULT_TIMEOUT=60' in config_content:
                pass  # Good
            else:
                correct_resolution = False
                resolution_issues.append("config.py has wrong TIMEOUT value")

            if 'MAX_RETRIES = 5' in config_content or 'MAX_RETRIES=5' in config_content:
                pass  # Good
            else:
                correct_resolution = False
                resolution_issues.append("config.py has wrong MAX_RETRIES value")

        if correct_resolution:
            criteria_passed += 1
            feedback_parts.append("✅ Correct resolution choices made (incoming changes accepted)")
        else:
            feedback_parts.append(f"❌ Incorrect resolution: {', '.join(resolution_issues)}")

        # Criterion 7: Both files were resolved (exist and not empty)
        both_files_exist = True
        if utils_content == "FILE_NOT_FOUND":
            both_files_exist = False
            feedback_parts.append("❌ utils.py not found")
        if config_content == "FILE_NOT_FOUND":
            both_files_exist = False
            feedback_parts.append("❌ config.py not found")

        if both_files_exist and utils_content and config_content:
            criteria_passed += 1
            feedback_parts.append("✅ Both conflicted files resolved")
        elif not both_files_exist:
            pass  # Already added feedback above
        else:
            feedback_parts.append("❌ One or more files are empty")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        logger.info(f"Merge conflict verification: {criteria_passed}/{total_criteria} criteria passed")
        logger.info(f"Score: {score}%, Passed: {passed}")

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
