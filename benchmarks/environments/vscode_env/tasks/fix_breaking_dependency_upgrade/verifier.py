#!/usr/bin/env python3
"""
Verifier for Fix Breaking Dependency Upgrade task

Checks:
1. requirements.txt updated to requests>=2.31.0
2. No old single-integer timeout patterns remain
3. New tuple timeout patterns exist (minimum 6)
4. All Python files are syntactically valid
"""

import sys
import os
import logging
import tempfile
import shutil
import re
import ast

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dependency_upgrade(traj, env_info, task_info):
    """
    Verify that requests dependency upgrade was completed correctly.
    
    Returns:
        dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='dependency_upgrade_verify_')
    
    try:
        # Files to check (as exported by export_result.sh)
        files_to_verify = {
            'requirements.txt': '/tmp/requirements.txt',
            'core.py': '/tmp/scraper_core.py',
            'utils.py': '/tmp/scraper_utils.py',
            'proxy_handler.py': '/tmp/scraper_proxy_handler.py',
            'test_scraper.py': '/tmp/tests_test_scraper.py'
        }
        
        local_files = {}
        
        # Copy all files from container
        for file_key, container_path in files_to_verify.items():
            local_path = os.path.join(temp_dir, file_key)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                        local_files[file_key] = f.read()
                else:
                    logger.warning(f"File {file_key} not found or empty")
                    local_files[file_key] = ""
            except Exception as e:
                logger.warning(f"Failed to copy {file_key}: {e}")
                local_files[file_key] = ""
        
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 4
        
        # ========================================
        # Criterion 1: requirements.txt updated to >=2.31.0
        # ========================================
        req_content = local_files.get('requirements.txt', '')
        
        if not req_content or len(req_content.strip()) < 5:
            feedback_parts.append("❌ requirements.txt not found or empty")
            requirements_ok = False
        else:
            # Parse version from requirements.txt
            requests_pattern = r'requests\s*([><=!]+)\s*(\d+\.\d+\.\d+)'
            matches = re.findall(requests_pattern, req_content, re.IGNORECASE)
            
            requirements_ok = False
            if matches:
                operator, version_str = matches[0]
                try:
                    major, minor, patch = map(int, version_str.split('.'))
                    
                    # Check if version is >= 2.31.0
                    if major > 2 or (major == 2 and minor >= 31):
                        criteria_passed += 1
                        feedback_parts.append(f"✅ requirements.txt updated to requests{operator}{version_str}")
                        requirements_ok = True
                    else:
                        feedback_parts.append(f"❌ requests version {version_str} too old (need >=2.31.0)")
                except ValueError:
                    feedback_parts.append(f"❌ Could not parse version: {version_str}")
            else:
                feedback_parts.append("❌ requests package not found in requirements.txt")
        
        # ========================================
        # Criterion 2: No old timeout patterns remain
        # ========================================
        # Old pattern: timeout=<integer> (not in a tuple)
        # Match: timeout=30 or timeout = 20, etc.
        # Don't match: timeout=(10, 30) or timeout = (5, 25)
        old_timeout_pattern = r'timeout\s*=\s*(\d+)\s*[,\)]'
        
        python_files = ['core.py', 'utils.py', 'proxy_handler.py', 'test_scraper.py']
        remaining_old_patterns = 0
        old_pattern_locations = []
        
        for pyfile in python_files:
            content = local_files.get(pyfile, '')
            if content:
                # Find all old-style timeout patterns
                matches = re.finditer(old_timeout_pattern, content)
                for match in matches:
                    remaining_old_patterns += 1
                    line_num = content[:match.start()].count('\n') + 1
                    old_pattern_locations.append(f"{pyfile}:L{line_num}")
        
        if remaining_old_patterns == 0:
            criteria_passed += 1
            feedback_parts.append("✅ No old single-integer timeout patterns found")
        else:
            locations_str = ", ".join(old_pattern_locations[:3])
            feedback_parts.append(f"❌ Found {remaining_old_patterns} old timeout patterns: {locations_str}")
        
        # ========================================
        # Criterion 3: New tuple timeout patterns exist (minimum 6)
        # ========================================
        # New pattern: timeout=(<num>, <num>) or timeout = (x, y)
        new_timeout_pattern = r'timeout\s*=\s*\([^)]+\)'
        
        total_new_patterns = 0
        new_pattern_locations = []
        
        for pyfile in python_files:
            content = local_files.get(pyfile, '')
            if content:
                matches = re.finditer(new_timeout_pattern, content)
                file_count = 0
                for match in matches:
                    total_new_patterns += 1
                    file_count += 1
                if file_count > 0:
                    new_pattern_locations.append(f"{pyfile}:{file_count}")
        
        if total_new_patterns >= 6:
            criteria_passed += 1
            locations_str = ", ".join(new_pattern_locations)
            feedback_parts.append(f"✅ Found {total_new_patterns} tuple timeout patterns: {locations_str}")
        else:
            feedback_parts.append(f"❌ Expected at least 6 tuple timeout patterns, found only {total_new_patterns}")
        
        # ========================================
        # Criterion 4: All Python files are syntactically valid
        # ========================================
        syntax_errors = []
        
        for pyfile in python_files:
            content = local_files.get(pyfile, '')
            if content:
                try:
                    ast.parse(content)
                except SyntaxError as e:
                    syntax_errors.append(f"{pyfile}:L{e.lineno}: {e.msg}")
        
        if len(syntax_errors) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ All Python files are syntactically valid")
        else:
            error_summary = "; ".join(syntax_errors[:2])
            feedback_parts.append(f"❌ Syntax errors: {error_summary}")
        
        # ========================================
        # Calculate final score and pass/fail
        # ========================================
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria  # All criteria must pass
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification result: {criteria_passed}/{total_criteria} criteria passed")
        
        return {
            "passed": passed,
            "score": score,
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
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
