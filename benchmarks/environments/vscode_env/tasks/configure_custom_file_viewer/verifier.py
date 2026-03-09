#!/usr/bin/env python3
"""
Verifier for configure_custom_file_viewer@1
Checks if agent successfully configured SQLite viewer and extracted data
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    get_installed_extensions,
    check_extension_installed,
    parse_vscode_settings,
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_custom_file_viewer(traj, env_info, task_info):
    """
    Verify that the agent successfully configured SQLite viewer and extracted data
    
    Checks:
    1. SQLite extension installed (1.5 points)
    2. File associations configured (1.0 points) - optional
    3. Investigation notes filled correctly (1.5 points)
    
    Returns:
        dict: {
            'passed': bool,
            'score': int (0-100),
            'feedback': str
        }
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_sqlite_')
    
    try:
        feedback_parts = []
        score = 0.0
        max_score = 4.0  # Four main criteria
        
        EXTENSIONS_DIR = "/home/ga/.vscode/extensions"
        WORKSPACE_SETTINGS = "/home/ga/workspace/db_debug/.vscode/settings.json"
        USER_SETTINGS = "/home/ga/.config/Code/User/settings.json"
        NOTES_FILE = "/home/ga/workspace/db_debug/investigation_notes.txt"
        
        # Copy exported files
        try:
            notes_local = os.path.join(temp_dir, "investigation_notes.txt")
            copy_from_env("/tmp/vscode_export/investigation_notes.txt", notes_local)
        except Exception as e:
            logger.warning(f"Failed to copy investigation notes: {e}")
            notes_local = None
        
        try:
            extensions_list_local = os.path.join(temp_dir, "installed_extensions.txt")
            copy_from_env("/tmp/vscode_export/installed_extensions.txt", extensions_list_local)
        except Exception as e:
            logger.warning(f"Failed to copy extensions list: {e}")
            extensions_list_local = None
        
        try:
            workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
            copy_from_env("/tmp/vscode_export/workspace_settings.json", workspace_settings_local)
        except Exception as e:
            logger.debug(f"No workspace settings found: {e}")
            workspace_settings_local = None
        
        try:
            user_settings_local = os.path.join(temp_dir, "user_settings.json")
            copy_from_env("/tmp/vscode_export/user_settings.json", user_settings_local)
        except Exception as e:
            logger.debug(f"No user settings found: {e}")
            user_settings_local = None
        
        # Criterion 1: Check if SQLite extension is installed (1.5 points)
        logger.info("Checking for SQLite viewer extension installation...")
        extension_installed = False
        installed_ext_name = None
        
        sqlite_extensions = [
            'alexcvzz.vscode-sqlite',
            'qwtel.sqlite-viewer',
            'mtxr.sqltools',
            'cweijan.vscode-database-client2'
        ]
        
        if extensions_list_local and os.path.exists(extensions_list_local):
            with open(extensions_list_local, 'r') as f:
                extensions_content = f.read().lower()
                for ext in sqlite_extensions:
                    if ext.lower() in extensions_content:
                        extension_installed = True
                        installed_ext_name = ext
                        break
        
        if extension_installed:
            score += 1.5
            feedback_parts.append(f"✅ SQLite viewer extension installed: {installed_ext_name}")
            logger.info(f"Extension found: {installed_ext_name}")
        else:
            feedback_parts.append("❌ No SQLite viewer extension detected. Expected one of: alexcvzz.vscode-sqlite, qwtel.sqlite-viewer, mtxr.sqltools")
            logger.warning("No SQLite extension found")
        
        # Criterion 2: Check file associations in settings (1.0 points) - OPTIONAL
        logger.info("Checking file association configuration...")
        file_association_configured = False
        
        # Check workspace settings first
        if workspace_settings_local and os.path.exists(workspace_settings_local):
            try:
                workspace_settings = parse_vscode_settings(workspace_settings_local)
                if 'files.associations' in workspace_settings:
                    associations = workspace_settings['files.associations']
                    if any(k in associations for k in ['*.sqlite', '*.db', '*.sqlite3']):
                        file_association_configured = True
                        score += 1.0
                        feedback_parts.append(f"✅ File associations configured in workspace settings")
                        logger.info(f"Workspace associations: {associations}")
            except Exception as e:
                logger.debug(f"Error parsing workspace settings: {e}")
        
        # Fallback to user settings
        if not file_association_configured and user_settings_local and os.path.exists(user_settings_local):
            try:
                user_settings = parse_vscode_settings(user_settings_local)
                if 'files.associations' in user_settings:
                    associations = user_settings['files.associations']
                    if any(k in associations for k in ['*.sqlite', '*.db', '*.sqlite3']):
                        file_association_configured = True
                        score += 1.0
                        feedback_parts.append(f"✅ File associations configured in user settings")
                        logger.info(f"User associations: {associations}")
            except Exception as e:
                logger.debug(f"Error parsing user settings: {e}")
        
        if not file_association_configured:
            feedback_parts.append("⚠️ No file associations configured (optional)")
            logger.info("No file associations found (this is optional)")
        
        # Criterion 3: Check if investigation notes were filled (1.5 points)
        logger.info("Checking investigation notes completion...")
        notes_complete = False
        correct_data = False
        
        if notes_local and os.path.exists(notes_local) and os.path.getsize(notes_local) > 0:
            notes_content = read_file_content(notes_local)
            
            # Check that placeholders were actually replaced
            still_has_placeholder = '[FILL IN]' in notes_content
            
            if not still_has_placeholder:
                # Basic completion: give 0.5 points for filling in anything
                score += 0.5
                
                # Check for correct information
                # Alice's ID should be 1, Bob's should be 2, Total users should be 3
                
                # Extract numbers from the notes
                numbers_in_notes = re.findall(r'\d+', notes_content)
                
                # Check if we have alice=1, bob=2, count=3
                has_alice_1 = False
                has_bob_2 = False
                has_count_3 = False
                
                # Look for "alice" followed by "1" (with some flexibility)
                alice_section = re.search(r"alice['\"]?s?\s*user_id[:\s]+(\d+)", notes_content, re.IGNORECASE)
                if alice_section and alice_section.group(1) == '1':
                    has_alice_1 = True
                elif 'alice' in notes_content.lower() and '1' in notes_content:
                    # Fallback: both alice and 1 present
                    has_alice_1 = True
                
                bob_section = re.search(r"bob['\"]?s?\s*user_id[:\s]+(\d+)", notes_content, re.IGNORECASE)
                if bob_section and bob_section.group(1) == '2':
                    has_bob_2 = True
                elif 'bob' in notes_content.lower() and '2' in notes_content:
                    has_bob_2 = True
                
                count_section = re.search(r"number\s+of\s+users[:\s]+(\d+)", notes_content, re.IGNORECASE)
                if count_section and count_section.group(1) == '3':
                    has_count_3 = True
                elif '3' in numbers_in_notes or 'three' in notes_content.lower():
                    has_count_3 = True
                
                if has_alice_1 and has_bob_2 and has_count_3:
                    score += 1.0  # Full credit for correct data
                    correct_data = True
                    feedback_parts.append("✅ Investigation notes completed with CORRECT data (alice=1, bob=2, total=3)")
                    logger.info("Notes filled with correct information")
                elif has_alice_1 or has_bob_2 or has_count_3:
                    score += 0.5  # Partial credit
                    feedback_parts.append("⚠️ Investigation notes partially correct")
                    logger.info("Notes partially correct")
                else:
                    feedback_parts.append("⚠️ Investigation notes filled but data appears incorrect")
                    logger.warning("Notes filled but incorrect data")
            else:
                feedback_parts.append("❌ Investigation notes still contain [FILL IN] placeholders")
                logger.warning("Notes not properly completed - placeholders remain")
        else:
            feedback_parts.append("❌ Investigation notes file not found or empty")
            logger.warning("Notes file missing or empty")
        
        # Calculate final score
        final_score = int((score / max_score) * 100)
        
        # Success requires at least 70% (2.8/4.0 points)
        # This means: extension installed (1.5) + notes filled correctly (1.5) = 3.0 = 75%
        # Or: extension (1.5) + notes partial (1.0) + associations (1.0) = 3.5 = 87.5%
        success = final_score >= 70
        
        # Combine feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {final_score} ({'PASS' if success else 'FAIL'})")
        
        return {
            "passed": success,
            "score": final_score,
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
