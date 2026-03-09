#!/usr/bin/env python3
"""
Verifier for Consolidate Experiments task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_workspace_cleaned(workspace_files_content: str) -> dict:
    """Verify experimental files are removed and final file exists"""
    
    results = {
        'v1_removed': 'rate_limiter_v1.py' not in workspace_files_content,
        'v2_removed': 'rate_limiter_v2.py' not in workspace_files_content,
        'v3_removed': 'rate_limiter_v3.py' not in workspace_files_content,
        'test_temp_removed': 'test_rate_limiter_temp.py' not in workspace_files_content,
        'debug_utils_removed': 'debug_utils.py' not in workspace_files_content,
        'benchmark_removed': 'benchmark_results.txt' not in workspace_files_content,
        'final_file_exists': 'rate_limiter.py' in workspace_files_content,
    }
    
    return results


def verify_code_quality(content: str) -> dict:
    """Verify code is clean: no debug prints, TODOs, commented code"""
    
    lines = content.split('\n')
    
    results = {
        'no_debug_prints': True,
        'no_todos': True,
        'no_fixmes': True,
        'no_large_comment_blocks': True,
    }
    
    # Check for debug prints containing "DEBUG"
    for line in lines:
        if 'print(' in line and 'DEBUG' in line.upper() and not line.strip().startswith('#'):
            results['no_debug_prints'] = False
            break
    
    # Check for TODOs
    if 'TODO' in content:
        results['no_todos'] = False
    
    # Check for FIXMEs
    if 'FIXME' in content:
        results['no_fixmes'] = False
    
    # Check for large commented blocks (3+ consecutive comment-only lines)
    consecutive_comments = 0
    max_consecutive = 0
    for line in lines:
        stripped = line.strip()
        # Count lines that are ONLY comments (not docstrings, not empty)
        if stripped.startswith('#') and len(stripped) > 1:
            consecutive_comments += 1
            max_consecutive = max(max_consecutive, consecutive_comments)
        else:
            consecutive_comments = 0
    
    if max_consecutive >= 3:
        results['no_large_comment_blocks'] = False
    
    return results


def verify_documentation(content: str) -> dict:
    """Verify proper documentation exists"""
    
    results = {
        'has_module_docstring': False,
        'has_class_docstring': False,
        'has_init_docstring': False,
        'has_method_docstring': False,
    }
    
    # Check for module docstring (first non-comment, non-blank line should be docstring)
    lines = content.split('\n')
    first_code_line_idx = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith('#'):
            first_code_line_idx = i
            break
    
    if first_code_line_idx >= 0:
        first_line = lines[first_code_line_idx].strip()
        if first_line.startswith('"""') or first_line.startswith("'''"):
            results['has_module_docstring'] = True
    
    # Check for class docstring
    class_pattern = r'class\s+RedisRateLimiter.*?:'
    class_match = re.search(class_pattern, content)
    if class_match:
        # Check next 300 chars after class definition for docstring
        start_pos = class_match.end()
        after_class = content[start_pos:start_pos+300]
        if '"""' in after_class or "'''" in after_class:
            results['has_class_docstring'] = True
    
    # Check for __init__ docstring
    init_pattern = r'def\s+__init__.*?:'
    init_match = re.search(init_pattern, content)
    if init_match:
        start_pos = init_match.end()
        after_init = content[start_pos:start_pos+200]
        if '"""' in after_init or "'''" in after_init:
            results['has_init_docstring'] = True
    
    # Check for is_allowed method docstring
    method_pattern = r'def\s+is_allowed.*?:'
    method_match = re.search(method_pattern, content)
    if method_match:
        start_pos = method_match.end()
        after_method = content[start_pos:start_pos+200]
        if '"""' in after_method or "'''" in after_method:
            results['has_method_docstring'] = True
    
    return results


def verify_requirements(content: str) -> dict:
    """Verify requirements.txt has redis dependency"""
    
    results = {
        'has_redis': False,
    }
    
    content_lower = content.lower()
    if 'redis' in content_lower:
        results['has_redis'] = True
    
    return results


def verify_git_state(git_log_content: str, git_status_content: str) -> dict:
    """Verify git commit and clean working directory"""
    
    results = {
        'commit_exists': False,
        'commit_message_correct': False,
        'working_dir_clean': False,
    }
    
    # Parse git log
    commits = []
    for line in git_log_content.strip().split('\n'):
        if line and line != "No commits":
            parts = line.split('|', 3)
            if len(parts) == 4:
                commits.append({
                    'hash': parts[0],
                    'message': parts[1],
                    'author': parts[2],
                    'date': parts[3]
                })
    
    # Check for new commit (should have at least 2: initial WIP + new one)
    if len(commits) >= 2:
        results['commit_exists'] = True
        
        # Check most recent commit message
        recent_commit = commits[0]
        message_lower = recent_commit['message'].lower()
        if 'redis' in message_lower and 'rate' in message_lower and 'limiter' in message_lower:
            results['commit_message_correct'] = True
    
    # Check working directory is clean
    if not git_status_content.strip():
        results['working_dir_clean'] = True
    
    return results


def verify_consolidate_experiments(traj, env_info, task_info):
    """
    Main verification function for consolidate_experiments task
    
    Returns scoring dict with breakdown of sub-criteria
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='consolidate_verify_')

    try:
        # Copy exported files
        workspace_files_local = os.path.join(temp_dir, "workspace_files.txt")
        git_log_local = os.path.join(temp_dir, "git_log.txt")
        git_status_local = os.path.join(temp_dir, "git_status.txt")
        rate_limiter_local = os.path.join(temp_dir, "rate_limiter_final.py")
        requirements_local = os.path.join(temp_dir, "requirements_final.txt")

        try:
            copy_from_env("/tmp/workspace_files.txt", workspace_files_local)
            copy_from_env("/tmp/git_log.txt", git_log_local)
            copy_from_env("/tmp/git_status.txt", git_status_local)
            copy_from_env("/tmp/rate_limiter_final.py", rate_limiter_local)
            copy_from_env("/tmp/requirements_final.txt", requirements_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy files: {str(e)}"}

        # Read file contents
        workspace_files_content = read_file_content(workspace_files_local)
        git_log_content = read_file_content(git_log_local)
        git_status_content = read_file_content(git_status_local)
        rate_limiter_content = read_file_content(rate_limiter_local)
        requirements_content = read_file_content(requirements_local)

        # Run all verification checks
        workspace_results = verify_workspace_cleaned(workspace_files_content)
        
        code_quality_results = {}
        doc_results = {}
        if rate_limiter_content and "File not found" not in rate_limiter_content:
            code_quality_results = verify_code_quality(rate_limiter_content)
            doc_results = verify_documentation(rate_limiter_content)
        else:
            # If file doesn't exist, mark all as failed
            code_quality_results = {
                'no_debug_prints': False,
                'no_todos': False,
                'no_fixmes': False,
                'no_large_comment_blocks': False,
            }
            doc_results = {
                'has_module_docstring': False,
                'has_class_docstring': False,
                'has_init_docstring': False,
                'has_method_docstring': False,
            }
        
        requirements_results = verify_requirements(requirements_content)
        git_results = verify_git_state(git_log_content, git_status_content)

        # Aggregate all results
        all_results = {
            **workspace_results,
            **code_quality_results,
            **doc_results,
            **requirements_results,
            **git_results,
        }

        # Calculate score
        total_checks = len(all_results)
        passed_checks = sum(1 for v in all_results.values() if v)
        score = int((passed_checks / total_checks * 100)) if total_checks > 0 else 0

        # Generate detailed feedback
        feedback_parts = []
        
        # Critical checks
        critical_passed = all([
            workspace_results.get('v1_removed'),
            workspace_results.get('v2_removed'),
            workspace_results.get('v3_removed'),
            workspace_results.get('final_file_exists'),
            code_quality_results.get('no_debug_prints'),
            code_quality_results.get('no_todos'),
        ])
        
        if critical_passed:
            feedback_parts.append("✅ Critical checks passed")
        else:
            feedback_parts.append("❌ Some critical checks failed")
        
        # File cleanup feedback
        files_removed = sum([
            workspace_results.get('v1_removed', False),
            workspace_results.get('v2_removed', False),
            workspace_results.get('v3_removed', False),
            workspace_results.get('test_temp_removed', False),
            workspace_results.get('debug_utils_removed', False),
            workspace_results.get('benchmark_removed', False),
        ])
        feedback_parts.append(f"Files removed: {files_removed}/6")
        
        # Code quality feedback
        if not code_quality_results.get('no_debug_prints'):
            feedback_parts.append("❌ Debug prints still present")
        if not code_quality_results.get('no_todos'):
            feedback_parts.append("❌ TODO comments still present")
        if code_quality_results.get('no_large_comment_blocks'):
            feedback_parts.append("✅ No large comment blocks")
        
        # Documentation feedback
        docs_added = sum([
            doc_results.get('has_module_docstring', False),
            doc_results.get('has_class_docstring', False),
            doc_results.get('has_init_docstring', False),
            doc_results.get('has_method_docstring', False),
        ])
        feedback_parts.append(f"Docstrings added: {docs_added}/4")
        
        # Git feedback
        if git_results.get('commit_exists'):
            feedback_parts.append("✅ New commit created")
            if git_results.get('commit_message_correct'):
                feedback_parts.append("✅ Commit message correct")
        else:
            feedback_parts.append("❌ No new commit found")
        
        # Requirements feedback
        if requirements_results.get('has_redis'):
            feedback_parts.append("✅ Requirements updated")
        
        passed = score >= 85

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": all_results
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
