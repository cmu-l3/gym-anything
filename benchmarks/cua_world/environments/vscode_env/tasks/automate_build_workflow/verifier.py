#!/usr/bin/env python3
"""
Verifier for Automate Build Workflow task
Checks if VSCode tasks.json properly automates the build workflow
"""

import json
import os
import sys
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_build_workflow(traj, env_info, task_info):
    """
    Verify the build workflow automation task.
    
    Checks:
    1. .vscode/tasks.json exists
    2. Valid JSON structure
    3. Contains a build/package/workflow task
    4. Includes cleanup step (rm -rf dist/)
    5. Includes validation step (validate_data.py)
    6. Includes processing step (process_data.py)
    7. Includes packaging step (tar/zip)
    8. Proper task type (shell or compound)
    9. Set as default build task
    
    Returns:
        dict: {
            'passed': bool,
            'score': int (0-100),
            'feedback': str
        }
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }

    temp_dir = tempfile.mkdtemp(prefix='build_workflow_verify_')
    
    try:
        # Copy tasks.json from /tmp (exported by export_result.sh)
        tasks_json_tmp = "/tmp/tasks.json"
        local_tasks_json = os.path.join(temp_dir, "tasks.json")
        
        try:
            copy_from_env(tasks_json_tmp, local_tasks_json)
        except Exception as e:
            logger.error(f"Failed to copy tasks.json: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access tasks.json: {str(e)}"
            }
        
        # Check if file exists and is not empty
        if not os.path.exists(local_tasks_json) or os.path.getsize(local_tasks_json) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ .vscode/tasks.json file not found or empty. You need to create this file to define the build task."
            }
        
        criteria_passed = 0
        total_criteria = 9
        feedback_parts = []
        
        # Criterion 1: File exists (already checked above)
        criteria_passed += 1
        feedback_parts.append("✓ tasks.json file exists")
        
        # Criterion 2: Valid JSON
        try:
            with open(local_tasks_json, 'r', encoding='utf-8') as f:
                tasks_config = json.load(f)
            criteria_passed += 1
            feedback_parts.append("✓ Valid JSON structure")
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 10,
                "feedback": f"❌ tasks.json is not valid JSON: {str(e)}"
            }
        except Exception as e:
            return {
                "passed": False,
                "score": 10,
                "feedback": f"❌ Error reading tasks.json: {str(e)}"
            }
        
        # Check for tasks array
        if 'tasks' not in tasks_config or not isinstance(tasks_config['tasks'], list):
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ tasks.json must have a 'tasks' array at the root level"
            }
        
        tasks = tasks_config['tasks']
        
        if len(tasks) == 0:
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ No tasks defined in tasks.json"
            }
        
        # Criterion 3: Find build/package/workflow task
        build_task = None
        for task in tasks:
            label = task.get('label', '').lower()
            if any(keyword in label for keyword in ['build', 'package', 'deploy', 'workflow']):
                build_task = task
                break
        
        if not build_task:
            # Try to find any task that might be the main one
            if len(tasks) == 1:
                build_task = tasks[0]
                feedback_parts.append(f"⚠ Found task '{build_task.get('label')}' but name doesn't contain 'build/package/workflow'")
            else:
                return {
                    "passed": False,
                    "score": 30,
                    "feedback": "❌ No task found with label containing 'build', 'package', 'workflow', or 'deploy'"
                }
        else:
            criteria_passed += 1
            feedback_parts.append(f"✓ Found build task: '{build_task.get('label')}'")
        
        # Analyze task configuration to get all commands
        task_type = build_task.get('type', '')
        command = build_task.get('command', '')
        depends_on = build_task.get('dependsOn', [])
        
        # Collect all commands from task and dependencies
        all_commands = []
        
        if task_type == 'shell' and command:
            all_commands.append(command)
        
        # For compound tasks or tasks with dependencies
        if depends_on:
            dep_list = depends_on if isinstance(depends_on, list) else [depends_on]
            for dep_label in dep_list:
                dep_task = next((t for t in tasks if t.get('label') == dep_label), None)
                if dep_task:
                    dep_cmd = dep_task.get('command', '')
                    if dep_cmd:
                        all_commands.append(dep_cmd)
        
        # Combine all commands into one string for checking
        combined_commands = ' '.join(all_commands).lower()
        
        # Also check the main task's command field and args
        task_str = json.dumps(build_task).lower()
        combined_commands += ' ' + task_str
        
        # Criterion 4: Includes cleanup step
        if any(keyword in combined_commands for keyword in ['rm -rf dist', 'rm dist', 'rmdir dist', 'del dist', 'clean']):
            criteria_passed += 1
            feedback_parts.append("✓ Includes cleanup step")
        else:
            feedback_parts.append("❌ Missing cleanup step (rm -rf dist/)")
        
        # Criterion 5: Includes validation step
        if 'validate_data.py' in combined_commands or 'validate_data' in combined_commands:
            criteria_passed += 1
            feedback_parts.append("✓ Includes validation step")
        else:
            feedback_parts.append("❌ Missing validation step (validate_data.py)")
        
        # Criterion 6: Includes processing step
        if 'process_data.py' in combined_commands or 'process_data' in combined_commands:
            criteria_passed += 1
            feedback_parts.append("✓ Includes processing step")
        else:
            feedback_parts.append("❌ Missing processing step (process_data.py)")
        
        # Criterion 7: Includes packaging step
        if any(keyword in combined_commands for keyword in ['tar', 'zip', 'deploy.tar.gz', 'package']):
            criteria_passed += 1
            feedback_parts.append("✓ Includes packaging step")
        else:
            feedback_parts.append("❌ Missing packaging step (tar/zip)")
        
        # Criterion 8: Proper task type
        if task_type in ['shell', 'process'] or depends_on:
            criteria_passed += 1
            if depends_on:
                feedback_parts.append("✓ Using compound task with dependencies")
            else:
                feedback_parts.append(f"✓ Using {task_type} task")
        else:
            feedback_parts.append(f"⚠ Unusual task type: {task_type}")
        
        # Criterion 9: Default build task
        group = build_task.get('group', {})
        is_default = False
        
        if isinstance(group, dict):
            is_default = group.get('kind') == 'build' and group.get('isDefault', False)
        elif isinstance(group, str) and group == 'build':
            # Simple group format - might not be default but acceptable
            is_default = True
        
        if is_default:
            criteria_passed += 1
            feedback_parts.append("✓ Set as default build task (can trigger with Ctrl+Shift+B)")
        else:
            feedback_parts.append("⚠ Not set as default build task (missing group.isDefault)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        
        # Task passes if:
        # - File exists and is valid JSON
        # - Has a task
        # - Includes validation, processing (required steps)
        # - Has at least 6/9 criteria passed
        required_steps = [
            'validate_data' in combined_commands,
            'process_data' in combined_commands
        ]
        
        passed = all(required_steps) and criteria_passed >= 6
        
        feedback = "\n".join(feedback_parts)
        
        if passed:
            feedback += "\n\n✅ Task automation successfully configured! The build workflow has been automated."
        else:
            feedback += "\n\n❌ Task configuration incomplete. Ensure all workflow steps are included."
        
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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
