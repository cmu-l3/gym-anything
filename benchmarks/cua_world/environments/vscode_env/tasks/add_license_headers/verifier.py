#!/usr/bin/env python3
"""
Verifier for Add License Headers task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def read_file_lines(filepath: str, max_lines: int = 25) -> list:
    """Read first N lines of a file."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            return [f.readline() for _ in range(max_lines)]
    except Exception as e:
        logger.error(f"Error reading {filepath}: {e}")
        return []


def check_python_header(filepath: str, filename: str) -> tuple:
    """
    Check if Python file has correct license header.
    Returns: (success, message, details_dict)
    """
    lines = read_file_lines(filepath, 25)
    
    if not lines:
        return False, "File is empty or unreadable", {}
    
    # Check if file starts with shebang
    has_shebang = lines[0].startswith('#!')
    search_start = 1 if has_shebang else 0
    
    # Look for required elements in first ~15 lines after potential shebang
    header_text = ''.join(lines[search_start:search_start+15])
    
    has_copyright = 'Copyright (c) 2024 DataTransformer Contributors' in header_text
    has_spdx = 'SPDX-License-Identifier: MIT' in header_text
    has_permission = 'Permission is hereby granted' in header_text
    
    # Check that header uses # comments (looking at non-empty lines after shebang)
    header_lines = [l for l in lines[search_start:search_start+12] if l.strip()]
    # Filter out docstrings
    comment_lines = [l for l in header_lines if l.strip() and not l.strip().startswith('"""') and not l.strip().startswith("'''")]
    
    if comment_lines:
        uses_hash_comments = all(l.strip().startswith('#') for l in comment_lines[:8])
    else:
        uses_hash_comments = False
    
    # For files with shebang, verify header is AFTER shebang
    correct_placement = True
    if has_shebang and filename == "main.py":
        # Check that copyright appears after line 0
        for i, line in enumerate(lines[1:6], start=1):
            if 'Copyright' in line:
                correct_placement = True
                break
        else:
            if 'Copyright' in lines[0]:
                correct_placement = False
    
    details = {
        'has_copyright': has_copyright,
        'has_spdx': has_spdx,
        'has_permission': has_permission,
        'uses_hash_comments': uses_hash_comments,
        'correct_placement': correct_placement,
        'has_shebang': has_shebang
    }
    
    if not (has_copyright and has_spdx and has_permission):
        return False, f"Missing required elements (copyright={has_copyright}, spdx={has_spdx}, permission={has_permission})", details
    
    if not uses_hash_comments:
        return False, "Header doesn't use # comment syntax", details
    
    if not correct_placement:
        return False, "Header placed before shebang (should be after)", details
    
    return True, "Valid Python header", details


def check_js_ts_header(filepath: str) -> tuple:
    """
    Check if JS/TS file has correct license header.
    Returns: (success, message, details_dict)
    """
    lines = read_file_lines(filepath, 20)
    
    if not lines:
        return False, "File is empty or unreadable", {}
    
    header_text = ''.join(lines[:15])
    
    has_copyright = 'Copyright (c) 2024 DataTransformer Contributors' in header_text
    has_spdx = 'SPDX-License-Identifier: MIT' in header_text
    has_permission = 'Permission is hereby granted' in header_text
    
    # Check that header uses // comments
    header_lines = [l for l in lines[:12] if l.strip()]
    if header_lines:
        uses_slash_comments = all(l.strip().startswith('//') for l in header_lines[:8])
    else:
        uses_slash_comments = False
    
    details = {
        'has_copyright': has_copyright,
        'has_spdx': has_spdx,
        'has_permission': has_permission,
        'uses_slash_comments': uses_slash_comments
    }
    
    if not (has_copyright and has_spdx and has_permission):
        return False, f"Missing required elements (copyright={has_copyright}, spdx={has_spdx}, permission={has_permission})", details
    
    if not uses_slash_comments:
        return False, "Header doesn't use // comment syntax", details
    
    return True, "Valid JS/TS header", details


def check_file_has_single_license(filepath: str) -> tuple:
    """
    Check that a file that already had a license wasn't modified (no duplicate).
    Returns: (is_single, count)
    """
    lines = read_file_lines(filepath, 30)
    copyright_count = sum(1 for line in lines if 'Copyright (c) 2024 DataTransformer Contributors' in line)
    return copyright_count == 1, copyright_count


def verify_license_headers(traj, env_info, task_info):
    """
    Verify that license headers were added correctly to all required files.
    
    Checks:
    1. Python files (3) have valid headers with # syntax
    2. JS/TS files (3) have valid headers with // syntax
    3. main.py has header after shebang
    4. All headers contain required content
    5. config.py (pre-existing license) wasn't modified
    6. Excluded files weren't modified
    
    Returns:
        dict with passed, score, feedback, metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='license_verify_')
    
    try:
        # Files that should have headers added
        python_files = [
            ('src/main.py', 'python', True),  # has shebang
            ('src/utils/logger.py', 'python', False),
            ('src/parsers/json_parser.py', 'python', False),
        ]
        
        js_ts_files = [
            ('src/transformers/mapper.js', 'js'),
            ('src/transformers/validator.js', 'js'),
            ('src/types.ts', 'ts'),
        ]
        
        # File that should remain unchanged (already has license)
        excluded_licensed = 'src/utils/config.py'
        
        results = {}
        total_checks = 0
        passed_checks = 0
        
        # Check Python files
        for relpath, file_type, has_shebang in python_files:
            total_checks += 1
            local_path = os.path.join(temp_dir, relpath.replace('/', '_'))
            container_path = f"/home/ga/workspace/data-transformer/{relpath}"
            
            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    results[relpath] = {'status': 'missing', 'reason': 'File not found or empty'}
                    continue
                
                filename = os.path.basename(relpath)
                success, message, details = check_python_header(local_path, filename)
                
                results[relpath] = {
                    'status': 'correct' if success else 'incorrect',
                    'reason': message,
                    'details': details
                }
                
                if success:
                    passed_checks += 1
                    
            except Exception as e:
                results[relpath] = {'status': 'error', 'reason': f'Copy failed: {str(e)}'}
        
        # Check JS/TS files
        for relpath, file_type in js_ts_files:
            total_checks += 1
            local_path = os.path.join(temp_dir, relpath.replace('/', '_'))
            container_path = f"/home/ga/workspace/data-transformer/{relpath}"
            
            try:
                copy_from_env(container_path, local_path)
                
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    results[relpath] = {'status': 'missing', 'reason': 'File not found or empty'}
                    continue
                
                success, message, details = check_js_ts_header(local_path)
                
                results[relpath] = {
                    'status': 'correct' if success else 'incorrect',
                    'reason': message,
                    'details': details
                }
                
                if success:
                    passed_checks += 1
                    
            except Exception as e:
                results[relpath] = {'status': 'error', 'reason': f'Copy failed: {str(e)}'}
        
        # Check that pre-licensed file wasn't modified (no duplicate headers)
        total_checks += 1
        local_config = os.path.join(temp_dir, 'config.py')
        container_config = f"/home/ga/workspace/data-transformer/{excluded_licensed}"
        
        try:
            copy_from_env(container_config, local_config)
            
            if os.path.exists(local_config):
                is_single, count = check_file_has_single_license(local_config)
                if is_single:
                    results[excluded_licensed] = {
                        'status': 'correctly_skipped',
                        'reason': 'License header not duplicated'
                    }
                    passed_checks += 1
                else:
                    results[excluded_licensed] = {
                        'status': 'error',
                        'reason': f'Header appears {count} times (should be 1 - file should not be modified)'
                    }
            else:
                results[excluded_licensed] = {'status': 'missing', 'reason': 'File not found'}
                
        except Exception as e:
            results[excluded_licensed] = {'status': 'error', 'reason': f'Verification failed: {str(e)}'}
        
        # Calculate score
        score = int((passed_checks / total_checks) * 100)
        success = score >= 85  # 85% threshold (6/7 or better)
        
        # Generate feedback
        feedback_parts = []
        
        if success:
            feedback_parts.append(f"✅ Successfully added license headers ({passed_checks}/{total_checks} checks passed)")
        else:
            feedback_parts.append(f"❌ Only {passed_checks}/{total_checks} checks passed (need 85%)")
        
        # Detailed feedback for failures
        python_successes = sum(1 for k, v in results.items() if k.endswith('.py') and k != excluded_licensed and v['status'] == 'correct')
        js_ts_successes = sum(1 for k, v in results.items() if (k.endswith('.js') or k.endswith('.ts')) and v['status'] == 'correct')
        
        feedback_parts.append(f"Python files: {python_successes}/3")
        feedback_parts.append(f"JS/TS files: {js_ts_successes}/3")
        
        # Report specific issues
        issues = []
        for file, result in results.items():
            if result['status'] not in ['correct', 'correctly_skipped']:
                issues.append(f"{file}: {result['reason']}")
        
        if issues:
            feedback_parts.append("Issues: " + "; ".join(issues[:3]))  # Limit to first 3 issues
        
        feedback = " | ".join(feedback_parts)
        
        metadata = {
            'files_processed': passed_checks,
            'total_checks': total_checks,
            'score': score,
            'details': results
        }
        
        return {
            "passed": success,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
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
