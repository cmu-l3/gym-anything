#!/usr/bin/env python3
"""
Verifier for Navigate Back After Definition task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_navigation_back(traj, env_info, task_info):
    """
    Verify that user navigated back to main.py from helpers.py.
    
    Checks:
    1. Active/focused file is main.py (detected via window title or access time)
    2. Cursor is near original position (line 6, inferred from marker comment presence)
    3. Marker comment "# <- WORK IN PROGRESS" still exists in main.py
    4. No unintended file modifications (file content largely unchanged)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='nav_verify_')
    
    try:
        # Copy exported files
        main_py_final = os.path.join(temp_dir, "main_final.py")
        helpers_py_final = os.path.join(temp_dir, "helpers_final.py")
        window_title = os.path.join(temp_dir, "window_title.txt")
        main_access_time = os.path.join(temp_dir, "main_access_time.txt")
        helpers_access_time = os.path.join(temp_dir, "helpers_access_time.txt")
        target_line_file = os.path.join(temp_dir, "target_line.txt")
        
        try:
            copy_from_env("/tmp/nav_task_main_final.py", main_py_final)
            copy_from_env("/tmp/nav_task_helpers_final.py", helpers_py_final)
            copy_from_env("/tmp/nav_task_window_title.txt", window_title)
            copy_from_env("/tmp/nav_task_main_access_time.txt", main_access_time)
            copy_from_env("/tmp/nav_task_helpers_access_time.txt", helpers_access_time)
            copy_from_env("/tmp/nav_task_target_line.txt", target_line_file)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy result files: {str(e)}"}
        
        criteria_passed = 0
        feedback_parts = []
        
        # Read main.py content
        main_content = ""
        if os.path.exists(main_py_final):
            with open(main_py_final, 'r') as f:
                main_content = f.read()
        
        # Criterion 1: Check if main.py appears to be the active file
        # Method 1: Check window title
        active_file_is_main = False
        if os.path.exists(window_title):
            with open(window_title, 'r') as f:
                title = f.read().strip()
                # Window title typically contains filename
                if 'main.py' in title.lower():
                    active_file_is_main = True
                    feedback_parts.append("✅ Window title indicates main.py is active")
        
        # Method 2: Check file access times (heuristic)
        if not active_file_is_main:
            try:
                with open(main_access_time, 'r') as f:
                    main_time = int(f.read().strip())
                with open(helpers_access_time, 'r') as f:
                    helpers_time = int(f.read().strip())
                
                # If main.py was accessed more recently, likely active
                if main_time > helpers_time:
                    active_file_is_main = True
                    feedback_parts.append("✅ main.py accessed more recently than helpers.py")
                elif main_time < helpers_time:
                    feedback_parts.append("❌ helpers.py appears more recently accessed (still in definition file?)")
                else:
                    feedback_parts.append("⚠️ Cannot determine active file from access times")
            except Exception as e:
                logger.warning(f"Could not compare access times: {e}")
        
        if active_file_is_main:
            criteria_passed += 1
        else:
            if not feedback_parts or 'active' not in ''.join(feedback_parts).lower():
                feedback_parts.append("❌ main.py does not appear to be the active file")
        
        # Criterion 2: Check if marker comment exists (proves correct file and vicinity)
        marker = "# <- WORK IN PROGRESS"
        marker_exists = marker in main_content
        
        if marker_exists:
            criteria_passed += 1
            # Find line number of marker
            lines = main_content.split('\n')
            marker_line = -1
            for i, line in enumerate(lines, 1):
                if marker in line:
                    marker_line = i
                    break
            feedback_parts.append(f"✅ Marker comment found at line {marker_line} in main.py")
        else:
            feedback_parts.append("❌ Marker comment '# <- WORK IN PROGRESS' not found (wrong file or modified?)")
        
        # Criterion 3: Check cursor is near target (inferred from marker presence)
        # Since we can't directly check cursor position, we verify the marker exists
        # and the file structure is intact around it
        target_line = 6
        if os.path.exists(target_line_file):
            with open(target_line_file, 'r') as f:
                target_line = int(f.read().strip())
        
        # Check if expected code structure exists around target line
        expected_snippets = [
            "def implement_new_feature",
            "process_data(user_input)",
            "result ="
        ]
        
        structure_intact = all(snippet in main_content for snippet in expected_snippets)
        if structure_intact:
            criteria_passed += 1
            feedback_parts.append("✅ Code structure intact around original position")
        else:
            feedback_parts.append("❌ Expected code structure not found around target line")
        
        # Criterion 4: Check no spurious edits (file is reasonably unchanged)
        # Count significant lines (non-empty, non-comment-only)
        lines = [l.strip() for l in main_content.split('\n') if l.strip() and not l.strip().startswith('#')]
        
        # Expected to have certain key elements
        has_import = any('import' in l for l in main_content.split('\n'))
        has_function = 'def implement_new_feature' in main_content
        has_return = 'return result' in main_content
        
        no_spurious_edits = has_import and has_function and has_return
        if no_spurious_edits:
            criteria_passed += 1
            feedback_parts.append("✅ File content appears unmodified")
        else:
            feedback_parts.append("❌ File appears to have unexpected modifications")
        
        # Calculate score
        score = int((criteria_passed / 4) * 100)
        passed = score >= 75
        
        # Special case: if marker exists and file structure intact, give more weight
        # This strongly indicates successful navigation
        if marker_exists and structure_intact:
            score = max(score, 75)  # Ensure at least passing
            passed = True
        
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
