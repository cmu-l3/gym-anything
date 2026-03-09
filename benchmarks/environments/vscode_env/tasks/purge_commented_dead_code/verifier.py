#!/usr/bin/env python3
"""
Verifier for purge_commented_dead_code@1 task
Checks that dead commented code is removed while preserving legitimate comments
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_patterns_removed(content, patterns):
    """Check that specific patterns are NOT in the content (should be removed)"""
    found = []
    for desc, pattern in patterns:
        if re.search(pattern, content, re.MULTILINE | re.IGNORECASE):
            found.append(desc)
    return found


def check_patterns_preserved(content, patterns):
    """Check that specific patterns ARE in the content (should be preserved)"""
    missing = []
    for desc, pattern in patterns:
        if not re.search(pattern, content, re.MULTILINE | re.IGNORECASE | re.DOTALL):
            missing.append(desc)
    return missing


def verify_dead_code_cleanup(traj, env_info, task_info):
    """
    Main verification function for dead code cleanup task.
    
    Checks multiple files for:
    1. Removal of commented-out dead code
    2. Preservation of docstrings
    3. Preservation of TODO/FIXME/NOTE comments
    4. Preservation of explanatory comments
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/comment_cleanup_project"
    
    # Define what should be removed and preserved for each file
    file_checks = {
        'src/main.py': {
            'remove': [
                ('old sync process_data function', r'#\s*def process_data\(data\):(?:\n#.*){0,5}'),
                ('old config file loading', r'#\s*with open\([\'"]config\.txt'),
                ('debug print statement', r'#\s*print\([\'"]Debug:.*Starting'),
            ],
            'preserve': [
                ('async process_data function', r'async def process_data'),
                ('main docstring', r'""".*Main application entry point.*"""'),
                ('TODO error handling comment', r'#\s*TODO:.*error handling'),
                ('FIXME old_main comment', r'#\s*FIXME:.*Remove this after'),
            ]
        },
        'src/utils.py': {
            'remove': [
                ('pandas import', r'#\s*import pandas as pd'),
                ('old datetime import', r'#\s*from datetime import datetime as dt(?:\s|$)'),
                ('debug_print function', r'#\s*def debug_print'),
                ('old validation if statement', r'#\s*if [\'"]id[\'"] in data:'),
                ('LOG_LEVEL variable', r'#\s*LOG_LEVEL\s*='),
                ('old strftime format', r'#\s*return dt\.now\(\)\.strftime'),
            ],
            'preserve': [
                ('format_output docstring', r'"""Format data for display"""'),
                ('validate_input docstring', r'"""Validate input data structure"""'),
                ('Check for required fields comment', r'#\s*Check for required fields'),
                ('current datetime import', r'from datetime import datetime(?:\s|$)'),
            ]
        },
        'src/data_processor.py': {
            'remove': [
                ('cache initialization', r'#\s*self\.cache\s*=\s*\{\}'),
                ('old upper() transformation', r'#\s*result\[[\'"]name[\'"]\]\s*=.*\.upper\(\)'),
                ('old value multiplication', r'#\s*result\[[\'"]value[\'"]\]\s*=.*\*\s*2'),
                ('batch_transform method', r'#\s*def batch_transform\(self'),
                ('AdvancedProcessor class', r'#\s*class AdvancedProcessor'),
                ('old normalize dict comprehension', r'#\s*data\s*=\s*\{k:\s*str\(v\)\.lower'),
            ],
            'preserve': [
                ('DataProcessor class', r'class DataProcessor:'),
                ('transform method docstring', r'"""Transform a single data item"""'),
                ('Apply business rules comment', r'#\s*Apply business rules'),
                ('stream_transform method', r'def stream_transform'),
            ]
        },
        'src/legacy_handler.py': {
            'remove': [
                ('handle_legacy_request_old function', r'#\s*def handle_legacy_request_old'),
                ('convert_field_names function', r'#\s*def convert_field_names'),
                ('experimental_handler function', r'#\s*def experimental_handler'),
                ('LegacyParser class', r'#\s*class LegacyParser'),
            ],
            'preserve': [
                ('NOTE deprecation comment', r'#\s*NOTE:.*scheduled for deprecation'),
                ('module docstring', r'""".*Legacy compatibility.*"""'),
                ('handle_legacy_request function', r'def handle_legacy_request\(request\)'),
                ('convert_to_v2 function', r'def convert_to_v2'),
            ]
        },
        'tests/test_main.py': {
            'remove': [
                ('unittest.mock import', r'#\s*from unittest\.mock import'),
                ('commented assertEqual', r'#\s*self\.assertEqual\(len\(results\)'),
                ('test_old_format method', r'#\s*def test_old_format'),
                ('TestLegacyMain class', r'#\s*class TestLegacyMain'),
            ],
            'preserve': [
                ('TestMain class docstring', r'"""Test cases for main functionality"""'),
                ('TODO fix test comment', r'#\s*TODO:.*Fix this test'),
                ('test_process_data method', r'def test_process_data'),
                ('This test needs improvement comment', r'#\s*This test needs improvement'),
            ]
        }
    }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_cleanup_')
    
    try:
        total_checks = 0
        passed_checks = 0
        all_errors = []
        all_feedback = []
        
        for filepath, checks in file_checks.items():
            full_path = os.path.join(workspace, filepath)
            local_path = os.path.join(temp_dir, filepath.replace('/', '_'))
            
            try:
                copy_from_env(full_path, local_path)
                
                if not os.path.exists(local_path) or os.path.getsize(local_path) == 0:
                    all_errors.append(f"{filepath}: File not found or empty")
                    continue
                
                content = read_file_content(local_path)
                if not content:
                    all_errors.append(f"{filepath}: Could not read file content")
                    continue
                
                # Check that patterns to remove are actually removed
                still_present = check_patterns_removed(content, checks['remove'])
                for item in still_present:
                    all_errors.append(f"{filepath}: Dead code still present - {item}")
                
                passed_checks += len(checks['remove']) - len(still_present)
                total_checks += len(checks['remove'])
                
                # Check that patterns to preserve are still there
                missing = check_patterns_preserved(content, checks['preserve'])
                for item in missing:
                    all_errors.append(f"{filepath}: Required code/comment removed - {item}")
                
                passed_checks += len(checks['preserve']) - len(missing)
                total_checks += len(checks['preserve'])
                
                # If this file is perfect, note it
                if not still_present and not missing:
                    all_feedback.append(f"✅ {filepath}: All checks passed")
                
            except Exception as e:
                logger.error(f"Error processing {filepath}: {e}", exc_info=True)
                all_errors.append(f"{filepath}: Verification error - {str(e)}")
                continue
        
        # Calculate score
        score = 0
        if total_checks > 0:
            score = int((passed_checks / total_checks) * 100)
        
        # Success threshold is 85%
        passed = score >= 85
        
        # Build feedback
        feedback_parts = []
        if passed:
            feedback_parts.append(f"✅ Task complete! ({passed_checks}/{total_checks} checks passed, {score}%)")
            # Add any successful file notes
            feedback_parts.extend(all_feedback[:3])
        else:
            feedback_parts.append(f"❌ Task incomplete ({passed_checks}/{total_checks} checks passed, {score}% - need 85%)")
            # Show first few errors as examples
            feedback_parts.append("Issues found:")
            for error in all_errors[:5]:
                feedback_parts.append(f"  • {error}")
            if len(all_errors) > 5:
                feedback_parts.append(f"  ... and {len(all_errors) - 5} more issues")
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
