#!/usr/bin/env python3
"""
Verifier for Jump to Line Number task
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


def verify_line_navigation(traj, env_info, task_info):
    """
    Verify that the agent successfully navigated to line 342 and marked it.
    
    Checks:
    1. File exists and was modified
    2. Marker comment '# CHECKPOINT' appears in the file
    3. Marker appears specifically on line 342
    4. Line 342 is non-empty and contains valid content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='line_nav_verify_')
    
    try:
        # Copy the main.py file from container
        container_path = "/home/ga/workspace/line_nav_task/main.py"
        local_file = os.path.join(temp_dir, "main.py")
        
        try:
            copy_from_env(container_path, local_file)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file: {str(e)}"}
        
        if not os.path.exists(local_file) or os.path.getsize(local_file) == 0:
            return {"passed": False, "score": 0, "feedback": "File not found or empty"}
        
        # Read file content
        content = read_file_content(local_file)
        if not content:
            return {"passed": False, "score": 0, "feedback": "Could not read file content"}
        
        lines = content.split('\n')
        
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: File has expected length (should still be around 342+ lines)
        if len(lines) >= 342:
            criteria_passed += 1
            feedback_parts.append(f"✅ File has {len(lines)} lines (expected ≥342)")
        else:
            feedback_parts.append(f"❌ File has only {len(lines)} lines (expected ≥342)")
        
        # Criterion 2: Marker comment '# CHECKPOINT' exists somewhere in file
        marker_found = False
        marker_line_number = -1
        
        for i, line in enumerate(lines, start=1):
            if '# CHECKPOINT' in line or '#CHECKPOINT' in line:
                marker_found = True
                marker_line_number = i
                break
        
        if marker_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Marker '# CHECKPOINT' found in file at line {marker_line_number}")
        else:
            feedback_parts.append("❌ Marker '# CHECKPOINT' not found in file")
        
        # Criterion 3: Marker appears specifically on line 342
        if len(lines) >= 342:
            line_342 = lines[341]  # 0-indexed, so line 342 is index 341
            
            if '# CHECKPOINT' in line_342 or '#CHECKPOINT' in line_342:
                criteria_passed += 1
                feedback_parts.append(f"✅ Marker found on correct line 342: '{line_342.strip()}'")
            else:
                if marker_found:
                    feedback_parts.append(f"❌ Marker found on line {marker_line_number}, not line 342. Line 342 contains: '{line_342.strip()[:50]}'")
                else:
                    feedback_parts.append(f"❌ No marker on line 342. Line 342 contains: '{line_342.strip()[:50]}'")
        else:
            feedback_parts.append("❌ File doesn't have 342 lines")
        
        # Criterion 4: Line 342 is non-empty and has content
        if len(lines) >= 342:
            line_342 = lines[341].strip()
            if line_342:
                criteria_passed += 1
                feedback_parts.append(f"✅ Line 342 is non-empty")
            else:
                feedback_parts.append("❌ Line 342 is empty")
        
        # Calculate score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75
        
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
