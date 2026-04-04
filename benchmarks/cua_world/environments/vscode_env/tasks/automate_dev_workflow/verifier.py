#!/usr/bin/env python3
"""
Verifier for Automate Dev Workflow task
"""

import sys
import os
import json
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_workflow_task(traj, env_info, task_info):
    """
    Verify that a valid VSCode task workflow was created.
    
    Checks:
    1. .vscode/tasks.json file exists
    2. Valid JSON structure with 'tasks' array
    3. At least one workflow task defined (compound or shell)
    4. Configuration includes npm install
    5. Configuration includes npm test
    6. Configuration includes npm run dev
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace_path = "/home/ga/dev-project"
    tasks_json_path = os.path.join(workspace_path, ".vscode", "tasks.json")
    
    # Create temp file for copied tasks.json
    temp_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()
    
    # Try to copy tasks.json from container
    try:
        copy_from_env(tasks_json_path, temp_path)
    except Exception as e:
        logger.error(f"Failed to copy tasks.json: {e}")
        # Also try from /tmp backup location
        try:
            copy_from_env("/tmp/tasks.json", temp_path)
        except Exception as e2:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ tasks.json not found at {tasks_json_path} (Error: {e})"
            }
    
    # Check if file exists and has content
    if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
        os.unlink(temp_path)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ tasks.json file is empty or not accessible"
        }
    
    # Parse JSON
    try:
        with open(temp_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        os.unlink(temp_path)
        return {
            "passed": False,
            "score": 10,
            "feedback": f"❌ Invalid JSON in tasks.json: {str(e)}"
        }
    except Exception as e:
        os.unlink(temp_path)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error reading tasks.json: {str(e)}"
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
    
    criteria_passed = 0
    max_criteria = 6
    feedback_parts = []
    
    # Criterion 1: Has 'tasks' array
    if "tasks" not in config:
        return {
            "passed": False,
            "score": 20,
            "feedback": "❌ tasks.json exists but missing 'tasks' array. Expected structure: {\"version\": \"2.0.0\", \"tasks\": [...]}"
        }
    
    criteria_passed += 1
    feedback_parts.append("✅ Valid JSON with 'tasks' array")
    
    if not isinstance(config["tasks"], list):
        return {
            "passed": False,
            "score": 25,
            "feedback": "❌ 'tasks' field must be an array"
        }
    
    if len(config["tasks"]) == 0:
        return {
            "passed": False,
            "score": 30,
            "feedback": "❌ 'tasks' array is empty. You need to define at least one task."
        }
    
    criteria_passed += 1
    feedback_parts.append(f"✅ Found {len(config['tasks'])} task(s) defined")
    
    # Find workflow task (either compound task with dependsOn or shell task with multiple commands)
    workflow_task = None
    task_type = None
    all_tasks = config["tasks"]
    
    # First, look for compound tasks (tasks with dependsOn)
    for task in all_tasks:
        if "dependsOn" in task and task["dependsOn"]:
            workflow_task = task
            task_type = "compound"
            break
    
    # If no compound task, look for shell tasks with chained commands
    if workflow_task is None:
        for task in all_tasks:
            if task.get("type") == "shell":
                command = str(task.get("command", "")).lower()
                # Check if it has multiple npm commands (using && or ;)
                if ("npm" in command or "install" in command) and \
                   ("&&" in command or ";" in command or "\n" in command):
                    workflow_task = task
                    task_type = "shell"
                    break
    
    if workflow_task is None:
        # Maybe there are separate tasks but not linked?
        task_labels = [t.get("label", "") for t in all_tasks]
        return {
            "passed": False,
            "score": 40,
            "feedback": f"❌ No workflow task found. You need either: (1) a compound task with 'dependsOn' field, or (2) a shell task with chained commands (using &&). Found tasks: {task_labels[:3]}"
        }
    
    criteria_passed += 1
    feedback_parts.append(f"✅ Workflow task found (type: {task_type})")
    
    # Extract all commands from the workflow
    all_commands_text = ""
    
    if task_type == "compound":
        # Get subtask labels from dependsOn
        subtask_refs = workflow_task.get("dependsOn", [])
        if isinstance(subtask_refs, str):
            subtask_refs = [subtask_refs]
        
        # Also add the main task's command if it has one
        if "script" in workflow_task:
            all_commands_text += " " + str(workflow_task.get("script", ""))
        if "command" in workflow_task:
            all_commands_text += " " + str(workflow_task.get("command", ""))
        
        # Find and process all referenced subtasks
        for task in all_tasks:
            task_label = task.get("label", "")
            if task_label in subtask_refs or task == workflow_task:
                # Extract commands from this task
                if task.get("type") == "npm":
                    script = task.get("script", "")
                    all_commands_text += " npm " + script
                elif task.get("type") == "shell":
                    cmd = task.get("command", "")
                    all_commands_text += " " + cmd
                else:
                    # Generic task type
                    if "command" in task:
                        all_commands_text += " " + str(task["command"])
                    if "script" in task:
                        all_commands_text += " " + str(task["script"])
    
    elif task_type == "shell":
        # For shell tasks, extract the command
        all_commands_text = workflow_task.get("command", "")
    
    # Normalize the commands text for checking
    all_commands_lower = all_commands_text.lower()
    
    # Criterion 4: Check for npm install
    has_install = (
        "npm install" in all_commands_lower or
        "npm i " in all_commands_lower or
        "npm i\n" in all_commands_lower or
        "npm i;" in all_commands_lower or
        "npm i&&" in all_commands_lower or
        'script": "install"' in all_commands_lower or
        '"install"' in all_commands_lower
    )
    
    if has_install:
        criteria_passed += 1
        feedback_parts.append("✅ Contains npm install")
    else:
        feedback_parts.append("❌ Missing npm install command")
    
    # Criterion 5: Check for npm test
    has_test = (
        "npm test" in all_commands_lower or
        "npm t " in all_commands_lower or
        "npm t\n" in all_commands_lower or
        "npm t;" in all_commands_lower or
        "npm t&&" in all_commands_lower or
        'script": "test"' in all_commands_lower or
        ('"test"' in all_commands_lower and "npm" in all_commands_lower)
    )
    
    if has_test:
        criteria_passed += 1
        feedback_parts.append("✅ Contains npm test")
    else:
        feedback_parts.append("❌ Missing npm test command")
    
    # Criterion 6: Check for npm run dev (or start)
    has_dev = (
        "npm run dev" in all_commands_lower or
        "npm dev" in all_commands_lower or
        "npm start" in all_commands_lower or
        "npm run start" in all_commands_lower or
        'script": "dev"' in all_commands_lower or
        'script": "start"' in all_commands_lower or
        ('"dev"' in all_commands_lower and "npm" in all_commands_lower)
    )
    
    if has_dev:
        criteria_passed += 1
        feedback_parts.append("✅ Contains npm run dev (or start)")
    else:
        feedback_parts.append("❌ Missing npm run dev command")
    
    # Calculate score
    score = int((criteria_passed / max_criteria) * 100)
    passed = criteria_passed == max_criteria
    
    # Add summary
    if passed:
        feedback_parts.insert(0, f"✅ All criteria passed ({criteria_passed}/{max_criteria})")
    else:
        feedback_parts.insert(0, f"⚠ Partial completion ({criteria_passed}/{max_criteria})")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
