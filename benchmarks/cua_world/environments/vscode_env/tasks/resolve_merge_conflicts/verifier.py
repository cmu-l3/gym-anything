#!/usr/bin/env python3
"""
Verifier for Resolve Merge Conflicts task
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


def has_conflict_markers(content):
    """Check if content contains Git conflict markers"""
    markers = ['<<<<<<<', '=======', '>>>>>>>']
    return any(marker in content for marker in markers)


def verify_python_syntax(content):
    """Check if Python code has valid syntax"""
    try:
        compile(content, '<string>', 'exec')
        return True
    except SyntaxError as e:
        logger.warning(f"Python syntax error: {e}")
        return False


def verify_merge_conflicts_resolved(traj, env_info, task_info):
    """
    Verify that merge conflicts were resolved correctly.

    Checks:
    1. No conflict markers in any file
    2. config.py has production database URL
    3. logger.py has both DEBUG and INFO logic
    4. README.md has both Docker and virtualenv instructions
    5. Python files have valid syntax
    6. No unmerged files in Git status
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='merge_verify_')

    try:
        # Define file paths
        repo_path = "/home/ga/workspace/merge_conflict_project"
        files_to_check = {
            'config.py': f"{repo_path}/src/config.py",
            'logger.py': f"{repo_path}/src/utils/logger.py",
            'README.md': f"{repo_path}/README.md"
        }

        # Copy files to local temp directory
        local_files = {}
        for name, container_path in files_to_check.items():
            local_path = os.path.join(temp_dir, name)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path):
                    local_files[name] = local_path
                else:
                    logger.warning(f"File not found after copy: {name}")
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")

        # Copy Git status files
        git_status_local = os.path.join(temp_dir, "git_status.txt")
        unmerged_local = os.path.join(temp_dir, "unmerged_files.txt")
        
        try:
            copy_from_env("/tmp/git_status.txt", git_status_local)
        except Exception as e:
            logger.warning(f"Failed to copy git_status.txt: {e}")
        
        try:
            copy_from_env("/tmp/unmerged_files.txt", unmerged_local)
        except Exception as e:
            logger.warning(f"Failed to copy unmerged_files.txt: {e}")

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Read file contents
        config_content = ""
        logger_content = ""
        readme_content = ""

        if 'config.py' in local_files:
            config_content = read_file_content(local_files['config.py'])
        if 'logger.py' in local_files:
            logger_content = read_file_content(local_files['logger.py'])
        if 'README.md' in local_files:
            readme_content = read_file_content(local_files['README.md'])

        # Criterion 1: No conflict markers in any file
        has_markers = False
        files_with_markers = []
        
        for name, content in [('config.py', config_content), 
                              ('logger.py', logger_content), 
                              ('README.md', readme_content)]:
            if has_conflict_markers(content):
                has_markers = True
                files_with_markers.append(name)
        
        if not has_markers:
            criteria_passed += 1
            feedback_parts.append("✅ No conflict markers found in any file")
        else:
            feedback_parts.append(f"❌ Conflict markers still present in: {', '.join(files_with_markers)}")

        # Criterion 2: config.py has production database URL
        if config_content:
            if 'db.prod.company.com:5432' in config_content or 'db.prod.company.com' in config_content:
                criteria_passed += 1
                feedback_parts.append("✅ config.py contains production database URL")
            else:
                if 'localhost' in config_content:
                    feedback_parts.append("❌ config.py still has localhost URL (should be production)")
                else:
                    feedback_parts.append("❌ config.py missing production database URL (db.prod.company.com:5432)")
        else:
            feedback_parts.append("❌ config.py not found or empty")

        # Criterion 3: logger.py has both DEBUG and INFO logic
        if logger_content:
            has_debug = 'DEBUG' in logger_content or 'logging.DEBUG' in logger_content
            has_info = 'INFO' in logger_content or 'logging.INFO' in logger_content
            
            if has_debug and has_info:
                criteria_passed += 1
                feedback_parts.append("✅ logger.py contains both DEBUG and INFO log levels")
            else:
                missing = []
                if not has_debug:
                    missing.append("DEBUG")
                if not has_info:
                    missing.append("INFO")
                feedback_parts.append(f"❌ logger.py missing: {', '.join(missing)} (need both)")
        else:
            feedback_parts.append("❌ logger.py not found or empty")

        # Criterion 4: README.md has both Docker and virtualenv instructions
        if readme_content:
            has_docker = 'docker' in readme_content.lower() or 'Docker' in readme_content
            has_venv = ('venv' in readme_content.lower() or 
                       'virtualenv' in readme_content.lower() or
                       'virtual environment' in readme_content.lower())
            
            if has_docker and has_venv:
                criteria_passed += 1
                feedback_parts.append("✅ README.md contains both Docker and virtualenv instructions")
            else:
                missing = []
                if not has_docker:
                    missing.append("Docker")
                if not has_venv:
                    missing.append("virtualenv")
                feedback_parts.append(f"❌ README.md missing: {', '.join(missing)} instructions (need both)")
        else:
            feedback_parts.append("❌ README.md not found or empty")

        # Criterion 5: Python files have valid syntax
        python_syntax_valid = True
        syntax_errors = []
        
        if config_content:
            if not verify_python_syntax(config_content):
                python_syntax_valid = False
                syntax_errors.append("config.py")
        
        if logger_content:
            if not verify_python_syntax(logger_content):
                python_syntax_valid = False
                syntax_errors.append("logger.py")
        
        if python_syntax_valid and (config_content or logger_content):
            criteria_passed += 1
            feedback_parts.append("✅ Python files have valid syntax")
        else:
            if syntax_errors:
                feedback_parts.append(f"❌ Syntax errors in: {', '.join(syntax_errors)}")
            else:
                feedback_parts.append("❌ Could not verify Python syntax")

        # Criterion 6: No unmerged files in Git status
        has_unmerged = False
        
        if os.path.exists(unmerged_local):
            with open(unmerged_local, 'r') as f:
                unmerged_content = f.read().strip()
                if unmerged_content:
                    has_unmerged = True
                    unmerged_files = unmerged_content.split('\n')
                    feedback_parts.append(f"❌ Git still shows unmerged files: {', '.join(unmerged_files[:3])}")
        
        if not has_unmerged:
            criteria_passed += 1
            feedback_parts.append("✅ No unmerged files in Git (conflicts resolved)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 83  # Need 5/6 criteria = 83%

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
