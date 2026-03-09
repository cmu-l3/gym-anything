#!/usr/bin/env python3
"""
Verifier for automate_fullstack_dev_start@1 task
Checks that VSCode tasks.json was created correctly with proper automation workflow
"""

import json
import os
import sys
import logging
import tempfile
import shutil
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def verify_task_automation(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that the VSCode task automation was created correctly.
    
    Scoring breakdown:
    - tasks.json exists: 20 points
    - Valid JSON: 20 points
    - Individual tasks (clean-dev, init-database, start-backend): 15 points each = 45 points
    - Compound task with sequential dependencies: 15 points
    - Default build task configuration: 10 points
    
    Total: 100 points
    Pass threshold: 70 points
    
    Returns:
        Dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available from environment"
        }
    
    score = 0.0
    max_score = 100.0
    feedback_parts = []
    
    # Define container paths
    tasks_json_path = "/home/ga/workspace/fullstack-project/.vscode/tasks.json"
    db_path = "/tmp/dev.db"
    
    temp_dir = None
    
    try:
        # Create temp directory for verification
        temp_dir = tempfile.mkdtemp(prefix='vscode_verify_automation_')
        local_tasks_json = os.path.join(temp_dir, 'tasks.json')
        
        # Step 1: Check if tasks.json exists (20 points)
        try:
            copy_from_env(tasks_json_path, local_tasks_json)
            
            if not os.path.exists(local_tasks_json) or os.path.getsize(local_tasks_json) == 0:
                feedback_parts.append("❌ tasks.json file not found or empty at .vscode/tasks.json")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "\n".join(feedback_parts)
                }
            
            score += 20.0
            feedback_parts.append("✅ tasks.json file exists (+20 pts)")
            
        except Exception as e:
            logger.error(f"Error copying tasks.json: {e}")
            feedback_parts.append(f"❌ tasks.json file not found: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        # Step 2: Parse and validate JSON structure (20 points)
        try:
            with open(local_tasks_json, 'r', encoding='utf-8') as f:
                tasks_config = json.load(f)
            
            score += 20.0
            feedback_parts.append("✅ tasks.json is valid JSON (+20 pts)")
            
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ tasks.json has invalid JSON syntax: {e}")
            return {
                "passed": False,
                "score": score,
                "feedback": "\n".join(feedback_parts)
            }
        except Exception as e:
            feedback_parts.append(f"❌ Error reading tasks.json: {e}")
            return {
                "passed": False,
                "score": score,
                "feedback": "\n".join(feedback_parts)
            }
        
        # Validate tasks array exists
        if "tasks" not in tasks_config or not isinstance(tasks_config["tasks"], list):
            feedback_parts.append("❌ tasks.json must have a 'tasks' array")
            return {
                "passed": False,
                "score": score,
                "feedback": "\n".join(feedback_parts)
            }
        
        tasks = tasks_config["tasks"]
        task_labels = [task.get("label", "") for task in tasks]
        
        logger.info(f"Found tasks: {task_labels}")
        
        # Step 3: Verify individual tasks (15 points each = 45 points total)
        required_tasks = {
            "clean-dev": {
                "found": False,
                "score": 0,
                "expected_command_parts": ["clean.sh"]
            },
            "init-database": {
                "found": False,
                "score": 0,
                "expected_command_parts": ["start_db.sh"]
            },
            "start-backend": {
                "found": False,
                "score": 0,
                "expected_command_parts": ["server.py", "python"]
            }
        }
        
        for task in tasks:
            label = task.get("label", "")
            task_type = task.get("type", "")
            command = task.get("command", "")
            args = task.get("args", [])
            
            # Convert args to string for searching
            args_str = " ".join(str(arg) for arg in args) if isinstance(args, list) else str(args)
            full_command = f"{command} {args_str}".lower()
            
            # Check clean-dev task
            if label == "clean-dev":
                required_tasks["clean-dev"]["found"] = True
                if "clean.sh" in full_command:
                    required_tasks["clean-dev"]["score"] = 15
                    feedback_parts.append("✅ 'clean-dev' task configured correctly (+15 pts)")
                else:
                    required_tasks["clean-dev"]["score"] = 8
                    feedback_parts.append("⚠️ 'clean-dev' task found but may not run clean.sh correctly (+8 pts)")
            
            # Check init-database task
            elif label == "init-database":
                required_tasks["init-database"]["found"] = True
                if "start_db.sh" in full_command:
                    required_tasks["init-database"]["score"] = 15
                    feedback_parts.append("✅ 'init-database' task configured correctly (+15 pts)")
                else:
                    required_tasks["init-database"]["score"] = 8
                    feedback_parts.append("⚠️ 'init-database' task found but may not run start_db.sh correctly (+8 pts)")
            
            # Check start-backend task
            elif label == "start-backend":
                required_tasks["start-backend"]["found"] = True
                has_server = "server.py" in full_command
                has_python = "python" in full_command or task_type == "python"
                
                # Check for environment variable (bonus)
                options = task.get("options", {})
                env_vars = options.get("env", {}) if isinstance(options, dict) else {}
                has_env = "APP_ENV" in env_vars or "app_env" in str(env_vars).lower()
                
                if has_server and has_python:
                    required_tasks["start-backend"]["score"] = 15
                    feedback_parts.append("✅ 'start-backend' task configured correctly (+15 pts)")
                elif has_server or has_python:
                    required_tasks["start-backend"]["score"] = 10
                    feedback_parts.append("⚠️ 'start-backend' task partially configured (+10 pts)")
                else:
                    required_tasks["start-backend"]["score"] = 5
                    feedback_parts.append("⚠️ 'start-backend' task found but configuration unclear (+5 pts)")
        
        # Add scores for individual tasks
        for task_name, task_info_dict in required_tasks.items():
            if not task_info_dict["found"]:
                feedback_parts.append(f"❌ Required task '{task_name}' not found (0 pts)")
            score += task_info_dict["score"]
        
        # Step 4: Check for compound task (15 points)
        compound_task_found = False
        compound_score = 0
        
        for task in tasks:
            label = task.get("label", "")
            
            # Look for compound task (various naming possibilities)
            if "start-dev-environment" in label.lower() or "dev-environment" in label.lower() or label == "start-dev-environment":
                compound_task_found = True
                
                depends_on = task.get("dependsOn", [])
                depends_order = task.get("dependsOrder", "")
                
                # Check if it depends on the required tasks
                depends_on_lower = [dep.lower() if isinstance(dep, str) else "" for dep in depends_on]
                
                has_all_deps = (
                    any("clean" in dep for dep in depends_on_lower) and
                    any("database" in dep or "db" in dep for dep in depends_on_lower) and
                    any("backend" in dep or "server" in dep for dep in depends_on_lower)
                )
                
                is_sequential = depends_order == "sequence"
                
                if has_all_deps and is_sequential:
                    compound_score = 15
                    feedback_parts.append("✅ Compound task 'start-dev-environment' configured with sequential dependencies (+15 pts)")
                elif has_all_deps:
                    compound_score = 10
                    feedback_parts.append("⚠️ Compound task found but may not run sequentially (missing dependsOrder: sequence) (+10 pts)")
                elif len(depends_on) > 0:
                    compound_score = 5
                    feedback_parts.append("⚠️ Compound task found but missing some dependencies (+5 pts)")
                else:
                    compound_score = 3
                    feedback_parts.append("⚠️ Compound task found but no dependencies configured (+3 pts)")
                
                break
        
        if not compound_task_found:
            feedback_parts.append("❌ Compound task 'start-dev-environment' not found (0 pts)")
        
        score += compound_score
        
        # Step 5: Check if compound task is set as default build task (10 points)
        default_build_score = 0
        
        if compound_task_found:
            for task in tasks:
                label = task.get("label", "")
                
                if "start-dev-environment" in label.lower() or "dev-environment" in label.lower():
                    group = task.get("group", {})
                    
                    # Check for default build task configuration
                    is_default_build = False
                    
                    if isinstance(group, dict):
                        kind = group.get("kind", "")
                        is_default = group.get("isDefault", False)
                        if kind == "build" and is_default:
                            is_default_build = True
                    elif isinstance(group, str) and group == "build":
                        # Also accept if just set to "build" group (partial credit)
                        default_build_score = 5
                        feedback_parts.append("⚠️ Compound task in build group but not set as default (+5 pts)")
                    
                    if is_default_build:
                        default_build_score = 10
                        feedback_parts.append("✅ Compound task set as default build task (+10 pts)")
                    
                    break
        else:
            feedback_parts.append("ℹ️ Cannot check default build task (compound task not found)")
        
        score += default_build_score
        
        # Bonus check: Database file exists (evidence tasks were executed)
        # This doesn't add to score but provides helpful feedback
        try:
            local_db = os.path.join(temp_dir, 'dev.db')
            copy_from_env(db_path, local_db)
            
            if os.path.exists(local_db) and os.path.getsize(local_db) > 0:
                feedback_parts.append("✨ [Bonus] Database file exists - tasks were successfully executed!")
        except:
            pass  # Database not required for verification, just nice to see
        
        # Calculate final result
        normalized_score = min(score, max_score)
        percentage = (normalized_score / max_score) * 100
        passed = normalized_score >= 70.0
        
        # Generate final feedback message
        feedback_message = "\n".join(feedback_parts)
        feedback_message += f"\n\n{'='*50}"
        feedback_message += f"\n📊 Final Score: {normalized_score:.1f}/{max_score} ({percentage:.1f}%)"
        feedback_message += f"\n{'='*50}"
        
        if passed:
            feedback_message += "\n✅ PASSED - Task automation configured correctly!"
        else:
            feedback_message += f"\n❌ FAILED - Need at least 70% to pass (got {percentage:.1f}%)"
        
        return {
            "passed": passed,
            "score": int(normalized_score),
            "feedback": feedback_message
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": int(score),
            "feedback": f"❌ Verification error: {str(e)}\n" + "\n".join(feedback_parts)
        }
    
    finally:
        # Cleanup temp directory
        if temp_dir and os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")
