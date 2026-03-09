#!/usr/bin/env python3
"""
Verifier for configure_env_switcher_with_safeguards@1
Checks if environment switching system is properly configured
"""

import sys
import os
import json
import logging
import tempfile
import shutil
import stat

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_env_switcher(traj, env_info, task_info):
    """
    Verify the environment switcher configuration.
    
    Checks:
    1. tasks.json exists with three switching tasks
    2. Tasks have appropriate labels
    3. settings.json has status bar or window customization
    4. Switching script exists (shell or python)
    5. Script is executable (for shell scripts)
    6. Script contains production confirmation logic
    7. Extension recommendations (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='env_switcher_verify_')
    
    try:
        feedback = []
        score = 0.0
        max_score = 10.0
        metadata = {}
        
        # Copy exported files
        tasks_file = os.path.join(temp_dir, "tasks.json")
        settings_file = os.path.join(temp_dir, "settings.json")
        extensions_file = os.path.join(temp_dir, "extensions.json")
        script_sh = os.path.join(temp_dir, "switch_env_script.sh")
        script_py = os.path.join(temp_dir, "switch_env_script.py")
        script_permissions = os.path.join(temp_dir, "script_permissions.txt")
        
        # Copy all files
        try:
            copy_from_env("/tmp/vscode_tasks.json", tasks_file)
        except Exception as e:
            logger.warning(f"Failed to copy tasks.json: {e}")
            
        try:
            copy_from_env("/tmp/vscode_settings.json", settings_file)
        except Exception as e:
            logger.warning(f"Failed to copy settings.json: {e}")
            
        try:
            copy_from_env("/tmp/vscode_extensions.json", extensions_file)
        except Exception as e:
            logger.warning(f"Failed to copy extensions.json: {e}")
            
        try:
            copy_from_env("/tmp/switch_env_script.sh", script_sh)
        except Exception as e:
            logger.debug(f"No .sh script: {e}")
            
        try:
            copy_from_env("/tmp/switch_env_script.py", script_py)
        except Exception as e:
            logger.debug(f"No .py script: {e}")
            
        try:
            copy_from_env("/tmp/script_permissions.txt", script_permissions)
        except Exception as e:
            logger.debug(f"No permissions file: {e}")
        
        # === Criterion 1 & 2: Check tasks.json (3.5 points) ===
        if not os.path.exists(tasks_file) or os.path.getsize(tasks_file) == 0:
            feedback.append("❌ .vscode/tasks.json does not exist or is empty")
            metadata["tasks_exists"] = False
        else:
            try:
                with open(tasks_file, 'r') as f:
                    tasks_config = json.load(f)
                
                tasks_list = tasks_config.get("tasks", [])
                task_labels = [t.get("label", "").lower() for t in tasks_list]
                
                metadata["task_count"] = len(tasks_list)
                metadata["task_labels"] = [t.get("label", "") for t in tasks_list]
                
                # Check for three environment tasks
                has_dev = any(("dev" in label or "development" in label) and "switch" in label 
                             for label in task_labels)
                has_staging = any("staging" in label and "switch" in label 
                                 for label in task_labels)
                has_prod = any(("prod" in label or "production" in label) and "switch" in label 
                              for label in task_labels)
                
                found_count = sum([has_dev, has_staging, has_prod])
                
                if found_count == 3:
                    feedback.append(f"✅ All three environment switching tasks found")
                    score += 3.5
                    metadata["all_tasks_found"] = True
                elif found_count >= 2:
                    feedback.append(f"⚠️ Found {found_count}/3 environment switching tasks")
                    score += 2.0
                    metadata["all_tasks_found"] = False
                elif found_count == 1:
                    feedback.append(f"⚠️ Found only {found_count}/3 environment switching tasks")
                    score += 1.0
                    metadata["all_tasks_found"] = False
                else:
                    feedback.append(f"❌ No environment switching tasks found. Task labels: {metadata['task_labels']}")
                    metadata["all_tasks_found"] = False
                
                metadata["has_dev_task"] = has_dev
                metadata["has_staging_task"] = has_staging
                metadata["has_prod_task"] = has_prod
                
            except json.JSONDecodeError as e:
                feedback.append(f"❌ tasks.json is not valid JSON: {e}")
                metadata["tasks_valid_json"] = False
            except Exception as e:
                feedback.append(f"❌ Error reading tasks.json: {e}")
                metadata["tasks_error"] = str(e)
        
        # === Criterion 3: Check settings.json (2 points) ===
        if not os.path.exists(settings_file) or os.path.getsize(settings_file) == 0:
            feedback.append("⚠️ .vscode/settings.json does not exist or is empty")
            metadata["settings_exists"] = False
        else:
            try:
                with open(settings_file, 'r') as f:
                    settings = json.load(f)
                
                has_statusbar = "statusBar.background" in settings or \
                              "workbench.colorCustomizations" in settings
                has_title = "window.title" in settings
                
                customization_count = sum([has_statusbar, has_title])
                
                if customization_count == 2:
                    feedback.append("✅ Both status bar and window title customization configured")
                    score += 2.0
                elif customization_count == 1:
                    feedback.append("⚠️ Partial customization found (need both status bar and window title)")
                    score += 1.0
                else:
                    feedback.append("❌ No status bar or window title customization found in settings.json")
                
                metadata["has_statusbar_config"] = has_statusbar
                metadata["has_title_config"] = has_title
                
            except json.JSONDecodeError as e:
                feedback.append(f"❌ settings.json is not valid JSON: {e}")
                metadata["settings_valid_json"] = False
            except Exception as e:
                feedback.append(f"⚠️ Error reading settings.json: {e}")
        
        # === Criterion 4: Check switching script exists (2 points) ===
        script_exists = False
        script_path = None
        script_type = None
        
        if os.path.exists(script_sh) and os.path.getsize(script_sh) > 10:
            script_exists = True
            script_path = script_sh
            script_type = "shell"
            feedback.append(f"✅ Switching script found: scripts/switch-env.sh")
            score += 2.0
        elif os.path.exists(script_py) and os.path.getsize(script_py) > 10:
            script_exists = True
            script_path = script_py
            script_type = "python"
            feedback.append(f"✅ Switching script found: scripts/switch_env.py")
            score += 2.0
        else:
            feedback.append("❌ No switching script found (checked switch-env.sh and switch_env.py)")
        
        metadata["script_exists"] = script_exists
        metadata["script_type"] = script_type
        
        # === Criterion 5: Check script is executable (0.5 points) ===
        if script_exists and script_type == "shell":
            # Check permissions from exported file
            if os.path.exists(script_permissions):
                with open(script_permissions, 'r') as f:
                    perm_content = f.read()
                
                # Look for executable permission (x flag)
                if 'x' in perm_content and 'switch-env.sh' in perm_content:
                    feedback.append("✅ Script is executable")
                    score += 0.5
                    metadata["script_executable"] = True
                else:
                    feedback.append("⚠️ Script exists but may not be executable (chmod +x needed)")
                    metadata["script_executable"] = False
            else:
                # As a fallback, we'll be lenient
                metadata["script_executable"] = "unknown"
        
        # === Criterion 6: Check production confirmation logic (2 points) ===
        if script_exists:
            try:
                with open(script_path, 'r') as f:
                    script_content = f.read().lower()
                
                # Look for confirmation patterns
                has_confirmation_check = (
                    ("confirm" in script_content or "confirmation" in script_content) and
                    ("prod" in script_content or "production" in script_content)
                )
                
                has_input_or_read = (
                    "read" in script_content or  # Bash read
                    "input(" in script_content    # Python input
                )
                
                has_safeguard = has_confirmation_check and has_input_or_read
                
                if has_safeguard:
                    feedback.append("✅ Script contains production confirmation safeguard")
                    score += 2.0
                    metadata["has_confirmation"] = True
                elif has_confirmation_check:
                    feedback.append("⚠️ Script mentions confirmation but may lack input prompt")
                    score += 1.0
                    metadata["has_confirmation"] = "partial"
                else:
                    feedback.append("❌ Script does not appear to have production confirmation safeguard")
                    metadata["has_confirmation"] = False
                    
            except Exception as e:
                feedback.append(f"⚠️ Could not analyze script content: {e}")
                metadata["script_analysis_error"] = str(e)
        
        # === Criterion 7: Check extensions.json (bonus 1 point) ===
        if os.path.exists(extensions_file) and os.path.getsize(extensions_file) > 10:
            try:
                with open(extensions_file, 'r') as f:
                    extensions = json.load(f)
                
                recommendations = extensions.get("recommendations", [])
                
                if recommendations:
                    feedback.append(f"✅ Extension recommendations configured: {len(recommendations)} extension(s)")
                    score += 1.0
                    metadata["extension_recommendations"] = recommendations
                else:
                    metadata["extension_recommendations"] = []
                    
            except Exception as e:
                logger.debug(f"Could not parse extensions.json: {e}")
        
        # Normalize score
        final_score = min(score / max_score, 1.0)
        success = final_score >= 0.7
        
        # Add summary
        if success:
            feedback.insert(0, f"🎉 Environment switcher successfully configured! (Score: {final_score:.0%})")
        else:
            feedback.insert(0, f"❌ Configuration incomplete (Score: {final_score:.0%}, need ≥70%)")
        
        return {
            "passed": success,
            "score": int(final_score * 100),
            "feedback": "\n".join(feedback),
            "metadata": metadata
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "metadata": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
