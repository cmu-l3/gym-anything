#!/usr/bin/env python3
"""
Verifier for Backup VLC Preferences task

Checks if VLC configuration files were properly backed up to preserve
user's customized settings for migration to a new computer.
"""

import sys
import os
import logging
import tempfile
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_backup_vlc_preferences(traj, env_info, task_info):
    """
    Verify that VLC preferences were backed up correctly.
    
    Checks:
    1. Backup directory exists with files
    2. Essential configuration files present (vlcrc, vlc-qt-interface.conf)
    3. Backed-up vlcrc contains custom settings (not empty/default)
    4. Files are readable and have reasonable size
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Create temp directory for verification files
    temp_dir = tempfile.mkdtemp(prefix='vlc_backup_verify_')
    
    try:
        # Copy the backup summary JSON first
        summary_file = os.path.join(temp_dir, 'backup_summary.json')
        try:
            copy_from_env("/tmp/vlc_backup_result/backup_summary.json", summary_file)
            
            import json
            with open(summary_file, 'r') as f:
                summary = json.load(f)
            
            logger.info(f"Backup summary: {summary}")
            
            if not summary.get('backup_directory_exists', False):
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ Backup directory not found at ~/Documents/vlc_backup/. "
                               "Did you create the backup? VLC config is in ~/.config/vlc/"
                }
        except Exception as e:
            logger.warning(f"Could not read backup summary: {e}")
        
        # Criterion 1: Backup directory exists with files
        backup_dir = os.path.join(temp_dir, 'vlc_backup')
        try:
            copy_from_env("/tmp/vlc_backup_result/vlc_backup", backup_dir)
            
            if os.path.isdir(backup_dir):
                file_count = len([f for f in Path(backup_dir).rglob('*') if f.is_file()])
                if file_count > 0:
                    criteria_met += 1
                    feedback_parts.append(f"✅ Backup directory exists ({file_count} files)")
                else:
                    feedback_parts.append("⚠️ Backup directory is empty")
            else:
                feedback_parts.append("❌ Backup directory not found")
        except Exception as e:
            logger.error(f"Error copying backup directory: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Backup directory not accessible: {str(e)}"
            }
        
        # Criterion 2: Essential files present
        vlcrc_backup = os.path.join(backup_dir, 'vlcrc')
        vlc_qt_backup = os.path.join(backup_dir, 'vlc-qt-interface.conf')
        
        essential_files_present = 0
        
        if os.path.exists(vlcrc_backup):
            essential_files_present += 1
            feedback_parts.append("✅ vlcrc backed up")
        else:
            feedback_parts.append("❌ vlcrc missing from backup")
        
        if os.path.exists(vlc_qt_backup):
            essential_files_present += 1
            feedback_parts.append("✅ vlc-qt-interface.conf backed up")
        else:
            feedback_parts.append("⚠️ vlc-qt-interface.conf missing")
        
        if essential_files_present >= 1:
            criteria_met += 1
        
        # Criterion 3: Backed-up vlcrc contains custom settings (not empty/corrupted)
        if os.path.exists(vlcrc_backup):
            try:
                vlcrc_size = os.path.getsize(vlcrc_backup)
                
                if vlcrc_size < 100:
                    feedback_parts.append(f"⚠️ vlcrc too small ({vlcrc_size} bytes) - may be empty")
                else:
                    # Read and verify content
                    with open(vlcrc_backup, 'r', errors='ignore') as f:
                        vlcrc_content = f.read()
                    
                    # Check for distinctive custom settings we created
                    required_settings = {
                        'volume=180': 'custom volume',
                        'loop=1': 'loop mode',
                        'key-faster=': 'custom hotkeys',
                        'snapshot-path=': 'snapshot path'
                    }
                    
                    settings_found = 0
                    missing_settings = []
                    
                    for setting, description in required_settings.items():
                        if setting in vlcrc_content:
                            settings_found += 1
                        else:
                            missing_settings.append(description)
                    
                    if settings_found >= 3:
                        criteria_met += 1
                        feedback_parts.append(f"✅ Custom settings preserved ({settings_found}/{len(required_settings)})")
                    elif settings_found >= 1:
                        feedback_parts.append(f"⚠️ Some settings found ({settings_found}/{len(required_settings)})")
                    else:
                        feedback_parts.append("❌ Custom settings missing - wrong file backed up?")
                        
            except Exception as e:
                logger.error(f"Error reading vlcrc backup: {e}")
                feedback_parts.append(f"❌ Could not read vlcrc backup: {str(e)}")
        
        # Criterion 4: File integrity (readable, non-empty, valid format)
        integrity_ok = True
        
        if os.path.exists(vlcrc_backup):
            try:
                with open(vlcrc_backup, 'r', errors='ignore') as f:
                    content = f.read()
                
                # Basic sanity checks
                if len(content) > 100 and ('[' in content or '=' in content):
                    # Looks like a config file
                    pass
                else:
                    integrity_ok = False
                    feedback_parts.append("⚠️ vlcrc format may be invalid")
            except Exception:
                integrity_ok = False
                feedback_parts.append("❌ vlcrc not readable")
        
        if os.path.exists(vlc_qt_backup):
            try:
                qt_size = os.path.getsize(vlc_qt_backup)
                if qt_size < 50:
                    integrity_ok = False
            except Exception:
                integrity_ok = False
        
        if integrity_ok:
            criteria_met += 1
            feedback_parts.append("✅ File integrity OK")
        else:
            feedback_parts.append("⚠️ File integrity concerns")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    # Add helpful context to feedback
    if passed:
        feedback += " | 🎉 VLC preferences successfully backed up! You can now restore these on a new machine."
    elif score >= 50:
        feedback += " | Task partially complete. Check if all essential files were copied."
    else:
        feedback += " | Backup incomplete. VLC config is in ~/.config/vlc/ (hidden folder)."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }