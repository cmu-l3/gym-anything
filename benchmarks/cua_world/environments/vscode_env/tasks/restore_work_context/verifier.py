#!/usr/bin/env python3
"""
Verifier for Restore Work Context task
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import sqlite3

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_open_files_from_vscdb(db_path):
    """
    Extract open file paths from VSCode's state.vscdb SQLite database.
    
    VSCode stores editor state in ItemTable with key 'editorspart.state'
    """
    open_files = []
    try:
        if not os.path.exists(db_path) or os.path.getsize(db_path) == 0:
            return open_files
        
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Query for editor state
        cursor.execute("SELECT value FROM ItemTable WHERE key LIKE '%editor%' OR key LIKE '%workbench%'")
        rows = cursor.fetchall()
        
        for row in rows:
            try:
                value_str = row[0]
                # The value is often JSON-encoded
                if 'user-auth-service' in value_str:
                    # Look for file paths in the JSON
                    if 'auth.py' in value_str:
                        open_files.append('auth.py')
                    if 'email_service.py' in value_str:
                        open_files.append('email_service.py')
                    if 'user.py' in value_str:
                        open_files.append('user.py')
            except Exception as e:
                logger.debug(f"Error parsing row: {e}")
                continue
        
        conn.close()
        
        # Remove duplicates
        open_files = list(set(open_files))
        
    except Exception as e:
        logger.warning(f"Error reading VSCode state database: {e}")
    
    return open_files


def extract_open_files_from_json(json_path):
    """
    Extract open file paths from workspace.json or other JSON state files.
    """
    open_files = []
    try:
        if not os.path.exists(json_path) or os.path.getsize(json_path) == 0:
            return open_files
        
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Convert to string to search for file names
        data_str = json.dumps(data).lower()
        
        if 'auth.py' in data_str:
            open_files.append('auth.py')
        if 'email_service.py' in data_str:
            open_files.append('email_service.py')
        if 'user.py' in data_str and 'models/user.py' in data_str:
            open_files.append('user.py')
        
    except Exception as e:
        logger.warning(f"Error parsing JSON state file: {e}")
    
    return open_files


def check_workspace_open(window_list_content):
    """Check if the user-auth-service workspace is open in VSCode."""
    if 'user-auth-service' in window_list_content.lower():
        return True
    if '/home/ga/projects/user-auth-service' in window_list_content:
        return True
    return False


def verify_restore_work_context(traj, env_info, task_info):
    """
    Verify that user-auth-service workspace is open with three target files.
    
    Checks:
    1. Workspace is open (window title check)
    2. auth.py is open as a tab
    3. email_service.py is open as a tab
    4. user.py is open as a tab
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_context_')

    try:
        # Copy exported data files
        window_list = os.path.join(temp_dir, "window_list.txt")
        workspace_state = os.path.join(temp_dir, "workspace_state.json")
        state_vscdb = os.path.join(temp_dir, "state.vscdb")
        recent_files = os.path.join(temp_dir, "recent_files.json")
        
        files_to_copy = [
            ("/tmp/window_list.txt", window_list),
            ("/tmp/vscode_workspace_state.json", workspace_state),
            ("/tmp/vscode_state.vscdb", state_vscdb),
            ("/tmp/vscode_recent_files.json", recent_files),
        ]
        
        for src, dst in files_to_copy:
            try:
                copy_from_env(src, dst)
            except Exception as e:
                logger.warning(f"Failed to copy {src}: {e}")
        
        criteria_passed = 0
        feedback_parts = []
        target_files = ['auth.py', 'email_service.py', 'user.py']
        files_found = set()
        
        # Criterion 1: Check workspace is open via window title
        workspace_open = False
        if os.path.exists(window_list) and os.path.getsize(window_list) > 0:
            with open(window_list, 'r') as f:
                window_content = f.read()
            
            workspace_open = check_workspace_open(window_content)
            
            if workspace_open:
                criteria_passed += 1
                feedback_parts.append("✅ user-auth-service workspace is open")
            else:
                feedback_parts.append("❌ user-auth-service workspace not detected in window title")
        else:
            feedback_parts.append("❌ Could not verify workspace (no window data)")
        
        # Criterion 2-4: Check which target files are open
        # Method 1: Check VSCode state database
        if os.path.exists(state_vscdb) and os.path.getsize(state_vscdb) > 0:
            db_files = extract_open_files_from_vscdb(state_vscdb)
            files_found.update(db_files)
            if db_files:
                logger.info(f"Files found in state DB: {db_files}")
        
        # Method 2: Check workspace state JSON
        if os.path.exists(workspace_state) and os.path.getsize(workspace_state) > 0:
            json_files = extract_open_files_from_json(workspace_state)
            files_found.update(json_files)
            if json_files:
                logger.info(f"Files found in workspace state: {json_files}")
        
        # Method 3: Check recent files JSON
        if os.path.exists(recent_files) and os.path.getsize(recent_files) > 0:
            recent_json_files = extract_open_files_from_json(recent_files)
            files_found.update(recent_json_files)
            if recent_json_files:
                logger.info(f"Files found in recent files: {recent_json_files}")
        
        # Score based on which files are found
        for target_file in target_files:
            if target_file in files_found:
                criteria_passed += 1
                feedback_parts.append(f"✅ {target_file} is open")
            else:
                feedback_parts.append(f"❌ {target_file} not detected as open")
        
        # Calculate score
        # Total criteria: 4 (1 workspace + 3 files)
        score = int((criteria_passed / 4) * 100)
        
        # Pass threshold: 75% means workspace + at least 2 files
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        # Add helpful message if task incomplete
        if not passed:
            if not workspace_open:
                feedback += " | Hint: Open /home/ga/projects/user-auth-service first"
            elif criteria_passed < 4:
                missing = [f for f in target_files if f not in files_found]
                if missing:
                    feedback += f" | Missing files: {', '.join(missing)}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
