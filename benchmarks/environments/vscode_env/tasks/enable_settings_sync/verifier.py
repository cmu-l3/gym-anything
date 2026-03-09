#!/usr/bin/env python3
"""
Verifier for VSCode Settings Sync Setup task
"""

import sys
import os
import json
import logging
import tempfile
import time
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_settings_sync(traj, env_info, task_info):
    """
    Verify that VSCode Settings Sync was configured.
    
    Checks:
    1. Settings Sync preferences appear in VSCode settings
    2. Sync state configuration exists in storage.json
    3. Sync-related configuration changes were made
    4. Settings indicate sync was attempted/enabled
    5. Sync preferences were configured (at least some options selected)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_sync_verify_')
    
    try:
        # Copy exported configuration files
        export_base = "/tmp/vscode_sync_export"
        
        local_settings = os.path.join(temp_dir, "settings.json")
        local_storage = os.path.join(temp_dir, "storage.json")
        local_sync_settings = os.path.join(temp_dir, "sync_settings.txt")
        
        files_copied = 0
        
        # Copy settings.json
        try:
            copy_from_env(f"{export_base}/settings.json", local_settings)
            if os.path.exists(local_settings) and os.path.getsize(local_settings) > 2:
                files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy settings.json: {e}")
        
        # Copy storage.json
        try:
            copy_from_env(f"{export_base}/storage.json", local_storage)
            if os.path.exists(local_storage) and os.path.getsize(local_storage) > 2:
                files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy storage.json: {e}")
        
        # Copy sync settings grep output
        try:
            copy_from_env(f"{export_base}/sync_settings.txt", local_sync_settings)
            files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy sync_settings.txt: {e}")
        
        if files_copied == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not access VSCode configuration files"
            }
        
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Check storage.json for sync configuration
        sync_state_found = False
        sync_enabled = False
        
        if os.path.exists(local_storage):
            try:
                with open(local_storage, 'r') as f:
                    storage = json.load(f)
                
                # Check for sync state configuration
                if 'userDataSync.state' in storage or 'userDataSync' in str(storage):
                    sync_state_found = True
                    feedback_parts.append("✅ Settings Sync state configuration found")
                    criteria_met += 1
                    
                    # Check if enabled
                    sync_state = storage.get('userDataSync.state', {})
                    if isinstance(sync_state, dict) and sync_state.get('enabled') == True:
                        sync_enabled = True
                        feedback_parts.append("✅ Settings Sync is enabled")
                        criteria_met += 1
                    elif isinstance(sync_state, dict) and 'enabled' in sync_state:
                        # Configuration was modified (even if not fully enabled)
                        feedback_parts.append("⚠️ Settings Sync configuration modified (partially enabled)")
                        criteria_met += 0.5
                    else:
                        feedback_parts.append("⚠️ Settings Sync configuration present but not enabled")
                else:
                    feedback_parts.append("❌ No Settings Sync configuration in storage.json")
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Could not parse storage.json: {e}")
        else:
            feedback_parts.append("❌ storage.json not found")
        
        # Criterion 2: Check for sync-related settings in settings.json
        sync_settings_in_config = False
        
        if os.path.exists(local_settings):
            try:
                with open(local_settings, 'r') as f:
                    settings = json.load(f)
                
                # Look for any sync-related settings
                sync_related_keys = [k for k in settings.keys() if 'sync' in k.lower()]
                if sync_related_keys:
                    sync_settings_in_config = True
                    feedback_parts.append(f"✅ Sync-related settings found: {', '.join(sync_related_keys[:3])}")
                    criteria_met += 1
                else:
                    # Check the grep output file
                    if os.path.exists(local_sync_settings):
                        with open(local_sync_settings, 'r') as f:
                            content = f.read()
                        if content and "No sync settings found" not in content:
                            feedback_parts.append("✅ Sync settings detected in configuration")
                            criteria_met += 1
                            sync_settings_in_config = True
                        else:
                            feedback_parts.append("⚠️ No sync-specific settings in configuration")
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Could not parse settings.json: {e}")
        
        # Criterion 3: Check for sync folder or sync data
        sync_folder_exists = False
        local_sync_dir = os.path.join(temp_dir, "sync")
        
        try:
            # Try to copy sync folder
            os.makedirs(local_sync_dir, exist_ok=True)
            
            # Try copying extensions.json from sync folder
            sync_extensions = os.path.join(temp_dir, "sync_extensions.json")
            try:
                copy_from_env(f"{export_base}/sync/extensions.json", sync_extensions)
                if os.path.exists(sync_extensions) and os.path.getsize(sync_extensions) > 2:
                    sync_folder_exists = True
                    feedback_parts.append("✅ Sync data folder exists with content")
                    criteria_met += 1
            except:
                pass
            
            if not sync_folder_exists:
                # Check if any sync files exist
                try:
                    copy_from_env(f"{export_base}/sync/settings.json", os.path.join(temp_dir, "sync_settings_data.json"))
                    if os.path.exists(os.path.join(temp_dir, "sync_settings_data.json")):
                        sync_folder_exists = True
                        feedback_parts.append("✅ Sync data present")
                        criteria_met += 1
                except:
                    feedback_parts.append("⚠️ No sync data folder found (may require authentication)")
        except Exception as e:
            feedback_parts.append("⚠️ Sync folder not accessible (typical without authentication)")
        
        # Criterion 4: Check for authentication provider configuration
        auth_provider_found = False
        
        if os.path.exists(local_storage):
            try:
                with open(local_storage, 'r') as f:
                    storage = json.load(f)
                
                if 'userDataSync.authenticationProviders' in storage:
                    auth_providers = storage['userDataSync.authenticationProviders']
                    if auth_providers and len(auth_providers) > 0:
                        auth_provider_found = True
                        feedback_parts.append(f"✅ Authentication provider configured: {auth_providers}")
                        criteria_met += 1
                    else:
                        feedback_parts.append("⚠️ Authentication provider field exists but empty")
                        criteria_met += 0.5
                else:
                    feedback_parts.append("⚠️ No authentication provider configured")
            except:
                pass
        
        # Criterion 5: Verify sync preferences were configured
        # Check if settings indicate sync options were selected
        preferences_configured = False
        
        if os.path.exists(local_storage):
            try:
                with open(local_storage, 'r') as f:
                    storage = json.load(f)
                
                # Look for sync preferences (what to sync)
                storage_str = json.dumps(storage)
                
                # Check for indicators that sync configuration was accessed/modified
                sync_indicators = ['sync', 'settings', 'extensions', 'keybindings', 'snippets']
                matches = sum(1 for indicator in sync_indicators if indicator in storage_str.lower())
                
                if matches >= 3:
                    preferences_configured = True
                    feedback_parts.append("✅ Sync preferences appear to be configured")
                    criteria_met += 1
                elif matches >= 1:
                    feedback_parts.append("⚠️ Some sync configuration detected")
                    criteria_met += 0.5
                else:
                    feedback_parts.append("❌ No sync preference configuration found")
            except:
                pass
        
        # Alternative check: if sync state was found and modified, give partial credit
        if not preferences_configured and sync_state_found:
            feedback_parts.append("⚠️ Sync configuration was accessed (partial credit)")
            criteria_met += 0.5
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = criteria_met >= 4.0  # Need 4/5 criteria (or 80%)
        
        # Build detailed feedback
        feedback = f"Settings Sync Configuration ({criteria_met:.1f}/{total_criteria} criteria):\n"
        feedback += "\n".join(feedback_parts)
        
        # Add diagnostic info for debugging
        if not passed:
            feedback += "\n\n📊 Diagnostic Info:"
            feedback += f"\n- Sync state found: {sync_state_found}"
            feedback += f"\n- Sync enabled: {sync_enabled}"
            feedback += f"\n- Sync settings in config: {sync_settings_in_config}"
            feedback += f"\n- Sync folder exists: {sync_folder_exists}"
            feedback += f"\n- Auth provider: {auth_provider_found}"
            feedback += f"\n- Preferences configured: {preferences_configured}"
        
        feedback += f"\n\n{'✅ PASS' if passed else '❌ FAIL'} - Score: {score}%"
        
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


def verify_task(env_state):
    """Entry point for gym-anything verification"""
    return verify_settings_sync(None, env_state, {})
