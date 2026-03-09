#!/usr/bin/env python3
"""
Verifier for setup_microservice_workspace@1
Validates that a proper multi-root workspace was created
"""

import sys
import os
import logging
import json
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_workspace(traj, env_info, task_info):
    """
    Verify that a multi-root workspace was correctly configured.
    
    Checks:
    1. Workspace file exists at /home/ga/projects/microservices.code-workspace
    2. File is valid JSON
    3. Contains exactly 3 folders
    4. Folders are: auth-service, shared-models, api-gateway
    5. (Bonus) Has workspace-level settings
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    workspace_path = "/home/ga/projects/microservices.code-workspace"
    temp_dir = tempfile.mkdtemp(prefix='workspace_verify_')
    
    try:
        local_workspace = os.path.join(temp_dir, "microservices.code-workspace")
        
        # Try to copy workspace file
        try:
            copy_from_env(workspace_path, local_workspace)
        except Exception as e:
            logger.error(f"Failed to copy workspace file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Workspace file not found at {workspace_path}"
            }
        
        # Check file exists and is not empty
        if not os.path.exists(local_workspace):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Workspace file not found or could not be copied"
            }
        
        if os.path.getsize(local_workspace) == 0:
            return {
                "passed": False,
                "score": 10,
                "feedback": "❌ Workspace file is empty"
            }
        
        criteria_passed = 0
        max_criteria = 5
        feedback_parts = []
        
        # Criterion 1: File exists (already validated above)
        criteria_passed += 1
        feedback_parts.append("✅ Workspace file exists")
        
        # Read and parse JSON
        try:
            with open(local_workspace, 'r', encoding='utf-8') as f:
                workspace_config = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ Invalid JSON in workspace file: {str(e)[:100]}"
            }
        except Exception as e:
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ Error reading workspace file: {str(e)[:100]}"
            }
        
        # Criterion 2: Valid JSON (already validated above)
        criteria_passed += 1
        feedback_parts.append("✅ Valid JSON structure")
        
        # Check for 'folders' key
        if "folders" not in workspace_config:
            return {
                "passed": False,
                "score": 40,
                "feedback": " | ".join(feedback_parts) + " | ❌ Missing 'folders' key in workspace config"
            }
        
        folders = workspace_config["folders"]
        
        if not isinstance(folders, list):
            return {
                "passed": False,
                "score": 40,
                "feedback": " | ".join(feedback_parts) + " | ❌ 'folders' must be a list"
            }
        
        # Criterion 3: Has exactly 3 folders
        folder_count = len(folders)
        if folder_count != 3:
            feedback_parts.append(f"❌ Expected 3 folders, found {folder_count}")
            score = min(40 + (folder_count * 10), 60)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_passed += 1
        feedback_parts.append("✅ Contains exactly 3 folders")
        
        # Extract folder names/paths
        folder_names = set()
        for folder in folders:
            if isinstance(folder, dict):
                # Folder can be {"path": "..."} or {"path": "...", "name": "..."}
                if "path" in folder:
                    path = folder["path"]
                    # Extract just the folder name from path
                    folder_name = os.path.basename(path.rstrip('/').rstrip('\\'))
                    folder_names.add(folder_name)
                elif "name" in folder:
                    folder_names.add(folder["name"])
            elif isinstance(folder, str):
                # Folder can be a direct string path
                folder_name = os.path.basename(folder.rstrip('/').rstrip('\\'))
                folder_names.add(folder_name)
        
        # Criterion 4: Check for required folders
        required_folders = {"auth-service", "shared-models", "api-gateway"}
        
        if required_folders.issubset(folder_names):
            criteria_passed += 1
            feedback_parts.append("✅ All required folders present: auth-service, shared-models, api-gateway")
        else:
            missing = required_folders - folder_names
            extra = folder_names - required_folders
            
            msg_parts = []
            if missing:
                msg_parts.append(f"missing: {', '.join(missing)}")
            if extra:
                msg_parts.append(f"extra: {', '.join(extra)}")
            
            feedback_parts.append(f"❌ Incorrect folders ({'; '.join(msg_parts)})")
            
            score = int((criteria_passed / max_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 5 (Bonus): Check for workspace-level settings
        has_settings = False
        if "settings" in workspace_config:
            settings = workspace_config.get("settings", {})
            if isinstance(settings, dict) and len(settings) > 0:
                has_settings = True
                criteria_passed += 1
                setting_keys = list(settings.keys())[:3]  # Show first 3 settings
                feedback_parts.append(f"✅ Workspace settings configured (e.g., {', '.join(setting_keys)})")
            else:
                feedback_parts.append("⚠️  No workspace settings (optional)")
        else:
            feedback_parts.append("⚠️  No workspace settings (optional)")
        
        # Calculate final score
        score = int((criteria_passed / max_criteria) * 100)
        
        # Pass threshold is 90% (need at least 4/5 criteria)
        passed = score >= 90
        
        if passed:
            feedback_parts.append("🎉 Multi-root workspace successfully configured!")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)[:200]}"
        }
    finally:
        # Clean up temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
