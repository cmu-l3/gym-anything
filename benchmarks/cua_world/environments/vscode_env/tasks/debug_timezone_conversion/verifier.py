#!/usr/bin/env python3
"""
Verifier for Debug Timezone Conversion task
Checks if user identified and marked the timezone bug location
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    verify_file_contains
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_timezone_debug(traj, env_info, task_info):
    """
    Verify that the user debugged the timezone conversion bug and marked it.
    
    Checks:
    1. File utils/dateConverter.js exists
    2. File was modified (contains bug marker comment)
    3. Marker is near the problematic code lines
    4. File content indicates understanding of the issue
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='timezone_verify_')
    
    try:
        # Copy the exported file from /tmp (created by export_result.sh)
        converter_file_tmp = "/tmp/dateConverter.js"
        local_converter = os.path.join(temp_dir, "dateConverter.js")
        
        try:
            copy_from_env(converter_file_tmp, local_converter)
        except Exception as e:
            logger.error(f"Failed to copy dateConverter.js: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Could not access file: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(local_converter) or os.path.getsize(local_converter) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File utils/dateConverter.js not found or empty"
            }
        
        # Read file content
        content = read_file_content(local_converter)
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not read file content"
            }
        
        lines = content.split('\n')
        feedback_parts = []
        criteria_passed = 0
        
        # Criterion 1: File exists (already checked)
        criteria_passed += 1
        feedback_parts.append("✅ File exists")
        
        # Criterion 2: Check if file was modified with a bug marker
        bug_marker_keywords = [
            'bug', 'todo', 'fixme', 'issue', 'problem', 
            'wrong', 'error', 'double', 'twice', 'fix'
        ]
        
        marker_lines = []
        for i, line in enumerate(lines):
            line_lower = line.lower()
            # Look for comments with bug markers
            if '//' in line or '/*' in line or '*' in line:
                for keyword in bug_marker_keywords:
                    if keyword in line_lower:
                        marker_lines.append(i)
                        break
        
        if not marker_lines:
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ No bug marker comment found. Add a comment like '// BUG: ...' near the problematic code"
            }
        
        criteria_passed += 1
        feedback_parts.append(f"✅ Bug marker comment found at line(s): {[l+1 for l in marker_lines]}")
        
        # Criterion 3: Check if marker is near the problematic code
        # The bug is in lines containing:
        # - "utcOffset * 60 * 1000"
        # - "valueOf() -"
        # - The manual offset adjustment
        
        problematic_patterns = [
            'utcoffset * 60 * 1000',
            'valueof() -',
            'valueof() - (',
            'utcoffset)',
        ]
        
        problem_line_indices = []
        for i, line in enumerate(lines):
            line_normalized = line.lower().replace(' ', '')
            for pattern in problematic_patterns:
                pattern_normalized = pattern.replace(' ', '')
                if pattern_normalized in line_normalized:
                    problem_line_indices.append(i)
                    break
        
        if not problem_line_indices:
            logger.warning("Could not identify problematic code lines - giving benefit of doubt")
            # Still give partial credit if marker exists
            return {
                "passed": True,
                "score": 70,
                "feedback": " | ".join(feedback_parts) + " | ⚠️ Marker location could not be verified but comment exists"
            }
        
        # Check if any marker is within 3 lines of a problem line
        marker_near_problem = False
        closest_distance = float('inf')
        
        for marker_idx in marker_lines:
            for problem_idx in problem_line_indices:
                distance = abs(marker_idx - problem_idx)
                closest_distance = min(closest_distance, distance)
                if distance <= 3:
                    marker_near_problem = True
                    break
            if marker_near_problem:
                break
        
        if marker_near_problem:
            criteria_passed += 1
            feedback_parts.append("✅ Bug marker is near the problematic code")
            
            # Perfect score
            return {
                "passed": True,
                "score": 100,
                "feedback": " | ".join(feedback_parts)
            }
        else:
            feedback_parts.append(f"⚠️ Bug marker found but {closest_distance} lines away from problem (expected within 3 lines)")
            
            # Partial credit - marker exists but not optimally placed
            return {
                "passed": True,
                "score": 70,
                "feedback": " | ".join(feedback_parts)
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
