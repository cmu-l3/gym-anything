#!/usr/bin/env python3
"""
Verifier for fix_cross_platform_paths@1
Checks that hardcoded Unix-style paths have been replaced with platform-agnostic alternatives
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cross_platform_paths(traj, env_info, task_info):
    """
    Verify that cross-platform path fixes were applied correctly.
    
    Checks:
    1. Hardcoded Unix-style paths eliminated (40 points)
    2. Platform-agnostic solutions added (40 points)
    3. Test script passes (20 points)
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_paths_')
    
    try:
        score = 0
        max_score = 100
        feedback_parts = []
        
        # File paths to check
        files_to_check = {
            'main.py': '/tmp/main_py.txt',
            'config_loader.py': '/tmp/config_loader_py.txt',
            'processor.py': '/tmp/processor_py.txt',
            'logger.py': '/tmp/logger_py.txt'
        }
        
        # Copy files to temp directory
        local_files = {}
        for filename, container_path in files_to_check.items():
            local_path = os.path.join(temp_dir, filename)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[filename] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {filename}: {e}")
        
        if not local_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No files found - task may not have been started"
            }
        
        # ===== CRITERION 1: Check hardcoded paths eliminated (40 points) =====
        hardcoded_patterns = [
            r'"config/database\.conf"',
            r'"logs/app\.log"',
            r'"config/"',
            r'"config/settings\.json"',
            r'"logs/application"',
            r'"logs/errors\.log"',
            r'"logs/debug\.log"',
            r'"output/processed"',
            r'"data/input"',
        ]
        
        total_hardcoded = 0
        hardcoded_details = []
        
        for filename, filepath in local_files.items():
            content = read_file_content(filepath)
            for pattern in hardcoded_patterns:
                matches = re.findall(pattern, content)
                if matches:
                    total_hardcoded += len(matches)
                    hardcoded_details.append(f"{filename}: {matches[0]}")
        
        # Also check for general pattern of hardcoded paths
        for filename, filepath in local_files.items():
            content = read_file_content(filepath)
            # Match patterns like "word/word" or "word/word.ext"
            general_matches = re.findall(r'["\'][\w]+/[\w/\.]+["\']', content)
            # Filter out false positives (like URLs, comments)
            for match in general_matches:
                # Check if this match isn't already caught by specific patterns
                if not any(re.search(pattern, match) for pattern in hardcoded_patterns):
                    # Additional check: make sure it looks like a file path
                    if any(x in match for x in ['config', 'logs', 'output', 'data', 'file', 'path', 'dir']):
                        total_hardcoded += 1
                        if len(hardcoded_details) < 3:  # Limit details
                            hardcoded_details.append(f"{filename}: {match}")
        
        # Score based on how many hardcoded paths remain
        if total_hardcoded == 0:
            score += 40
            feedback_parts.append("✅ No hardcoded Unix-style paths found (40/40)")
        elif total_hardcoded <= 2:
            score += 25
            feedback_parts.append(f"⚠️ Found {total_hardcoded} hardcoded paths: {', '.join(hardcoded_details[:2])} (25/40)")
        elif total_hardcoded <= 4:
            score += 15
            feedback_parts.append(f"⚠️ Found {total_hardcoded} hardcoded paths (15/40)")
        elif total_hardcoded <= 6:
            score += 5
            feedback_parts.append(f"❌ Found {total_hardcoded} hardcoded paths - many remain unfixed (5/40)")
        else:
            feedback_parts.append(f"❌ Found {total_hardcoded} hardcoded paths - task not completed (0/40)")
        
        # ===== CRITERION 2: Check platform-agnostic solutions added (40 points) =====
        pathlib_uses = 0
        ospath_uses = 0
        has_pathlib_import = False
        has_os_import = False
        
        for filename, filepath in local_files.items():
            content = read_file_content(filepath)
            
            # Count pathlib usage
            pathlib_uses += len(re.findall(r'Path\s*\(', content))
            # Count Path division operator (with quotes after, indicating path construction)
            pathlib_uses += len(re.findall(r'\)\s*/\s*["\']', content))
            
            # Count os.path.join usage
            ospath_uses += len(re.findall(r'os\.path\.join\s*\(', content))
            
            # Check imports
            if 'from pathlib import Path' in content or 'import pathlib' in content:
                has_pathlib_import = True
            if 'import os' in content and 'os.path' in content:
                has_os_import = True
        
        total_proper_uses = pathlib_uses + ospath_uses
        has_proper_imports = has_pathlib_import or has_os_import
        
        if total_proper_uses >= 7 and has_proper_imports:
            score += 40
            feedback_parts.append(f"✅ Found {total_proper_uses} platform-agnostic path constructions with proper imports (40/40)")
        elif total_proper_uses >= 5 and has_proper_imports:
            score += 35
            feedback_parts.append(f"✅ Found {total_proper_uses} platform-agnostic path constructions (35/40)")
        elif total_proper_uses >= 4 and has_proper_imports:
            score += 30
            feedback_parts.append(f"⚠️ Found {total_proper_uses} platform-agnostic path constructions - some files may be incomplete (30/40)")
        elif total_proper_uses >= 3:
            score += 20
            feedback_parts.append(f"⚠️ Found only {total_proper_uses} platform-agnostic path constructions (20/40)")
        elif total_proper_uses >= 1:
            score += 10
            feedback_parts.append(f"❌ Found only {total_proper_uses} platform-agnostic path constructions - task incomplete (10/40)")
        else:
            feedback_parts.append("❌ No platform-agnostic path constructions found (0/40)")
        
        if not has_proper_imports and total_proper_uses > 0:
            feedback_parts.append("⚠️ Warning: Path constructions found but missing proper imports")
        
        # ===== CRITERION 3: Test script passes (20 points) =====
        test_result_path = os.path.join(temp_dir, "test_result.txt")
        try:
            copy_from_env("/tmp/test_paths_result.txt", test_result_path)
            
            if os.path.exists(test_result_path):
                test_output = read_file_content(test_result_path)
                
                # Check if test passed (exit code 0)
                if "Test exit code: 0" in test_output or "3/3 tests passed" in test_output:
                    score += 20
                    feedback_parts.append("✅ Test script passed (20/20)")
                elif "2/3 tests passed" in test_output:
                    score += 15
                    feedback_parts.append("⚠️ Test script: 2/3 tests passed (15/20)")
                elif "1/3 tests passed" in test_output:
                    score += 10
                    feedback_parts.append("⚠️ Test script: 1/3 tests passed (10/20)")
                else:
                    # Check if test was at least attempted
                    if "Running cross-platform path verification" in test_output:
                        score += 5
                        feedback_parts.append("❌ Test script run but failed most checks (5/20)")
                    else:
                        feedback_parts.append("❌ Test script did not run successfully (0/20)")
            else:
                feedback_parts.append("❌ Test script results not found (0/20)")
        except Exception as e:
            logger.warning(f"Could not verify test results: {e}")
            feedback_parts.append("❌ Test script results unavailable (0/20)")
        
        # Calculate final result
        passed = score >= 70
        feedback = " | ".join(feedback_parts)
        
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
        cleanup_verification_temp(temp_dir)
