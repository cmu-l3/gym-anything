#!/usr/bin/env python3
"""
Verifier for VSCode Task Automation creation task
Checks if agent successfully created .vscode/tasks.json with correct configuration
"""

import sys
import os
import logging
import tempfile
import shutil
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task_automation(traj, env_info, task_info):
    """
    Verify that the agent correctly created a tasks.json file with appropriate task configuration
    
    Verification Criteria:
    1. .vscode directory exists (10%)
    2. tasks.json file exists (15%)
    3. Valid JSON syntax (15%)
    4. Has required structure (version, tasks array) (10%)
    5. Task has required fields (label, type, command) (20%)
    6. Task type is 'shell' (5%)
    7. Command contains 'python' (10%)
    8. References analyze_sales.py script (15%)
    9. Includes required arguments (10%)
    
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    
    feedback_parts = []
    reward = 0.0
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available in environment"
        }
    
    workspace_path = "/home/ga/workspace/sales_analysis"
    vscode_dir = f"{workspace_path}/.vscode"
    tasks_json_path = f"{vscode_dir}/tasks.json"
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_task_verify_')
    temp_tasks_file = None
    
    try:
        # ===== Check 1: Does .vscode directory exist? (10%) =====
        vscode_exists = False
        try:
            # Try to list directory contents to verify it exists
            temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            # We can't directly check directory, but we can try to copy tasks.json
            # If .vscode doesn't exist, tasks.json won't exist either
            # For now, we'll infer from tasks.json existence
            pass  # Will check via tasks.json
        except Exception as e:
            logger.debug(f"Could not check .vscode directory: {e}")
        
        # ===== Check 2: Does tasks.json file exist? (15%) =====
        temp_tasks_file = os.path.join(temp_dir, 'tasks.json')
        
        try:
            copy_from_env(tasks_json_path, temp_tasks_file)
            
            if not os.path.exists(temp_tasks_file):
                feedback_parts.append("❌ tasks.json file not found at .vscode/tasks.json")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
            if os.path.getsize(temp_tasks_file) == 0:
                feedback_parts.append("❌ tasks.json file is empty")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
            # If we got here, both .vscode and tasks.json exist
            vscode_exists = True
            reward += 0.10
            feedback_parts.append("✅ .vscode directory exists")
            
            reward += 0.15
            feedback_parts.append("✅ tasks.json file exists")
            
        except Exception as e:
            feedback_parts.append(f"❌ Could not find or copy tasks.json: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # ===== Check 3: Is it valid JSON? (15%) =====
        try:
            with open(temp_tasks_file, 'r', encoding='utf-8') as f:
                tasks_data = json.load(f)
            
            reward += 0.15
            feedback_parts.append("✅ tasks.json is valid JSON")
            
        except json.JSONDecodeError as e:
            feedback_parts.append(f"❌ Invalid JSON syntax: {str(e)}")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        except Exception as e:
            feedback_parts.append(f"❌ Error reading file: {str(e)}")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # ===== Check 4: Has required top-level structure? (10%) =====
        if not isinstance(tasks_data, dict):
            feedback_parts.append("❌ tasks.json must be a JSON object")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if "tasks" not in tasks_data:
            feedback_parts.append("❌ Missing 'tasks' array in tasks.json")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if not isinstance(tasks_data.get("tasks"), list):
            feedback_parts.append("❌ 'tasks' field must be an array")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if len(tasks_data["tasks"]) == 0:
            feedback_parts.append("❌ 'tasks' array is empty - must contain at least one task")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        reward += 0.10
        feedback_parts.append(f"✅ Valid structure with {len(tasks_data['tasks'])} task(s)")
        
        # ===== Check 5: Task has required fields? (20%) =====
        task = tasks_data["tasks"][0]  # Check first task
        
        if not isinstance(task, dict):
            feedback_parts.append("❌ Task must be a JSON object")
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        required_fields = ["label", "type", "command"]
        missing_fields = []
        
        for field in required_fields:
            if field not in task:
                missing_fields.append(field)
        
        if missing_fields:
            feedback_parts.append(f"❌ Task missing required fields: {', '.join(missing_fields)}")
            # Give partial credit if some fields present
            partial = (len(required_fields) - len(missing_fields)) / len(required_fields)
            reward += 0.20 * partial
        else:
            reward += 0.20
            feedback_parts.append("✅ Task has all required fields (label, type, command)")
        
        # ===== Check 6: Is task type 'shell'? (5%) =====
        task_type = task.get("type", "").lower()
        if task_type == "shell":
            reward += 0.05
            feedback_parts.append("✅ Task type is 'shell'")
        else:
            feedback_parts.append(f"❌ Task type is '{task.get('type')}' (expected 'shell')")
        
        # ===== Check 7: Command contains 'python'? (10%) =====
        command_str = str(task.get("command", "")).lower()
        if "python" in command_str:
            reward += 0.10
            feedback_parts.append("✅ Command includes 'python'")
        else:
            feedback_parts.append(f"❌ Command '{task.get('command')}' doesn't include 'python'")
        
        # ===== Check 8: References analyze_sales.py? (15%) =====
        # Check in command, args, and full task JSON
        full_task_text = json.dumps(task).lower()
        
        if "analyze_sales.py" in full_task_text:
            reward += 0.15
            feedback_parts.append("✅ Task references 'analyze_sales.py'")
        else:
            feedback_parts.append("❌ Task doesn't reference 'analyze_sales.py'")
        
        # ===== Check 9: Includes required arguments? (10%) =====
        # Check for key arguments in the task configuration
        required_args = ["--input", "--output", "sales_data.csv", "report.json"]
        found_args = []
        
        for arg in required_args:
            if arg.lower() in full_task_text:
                found_args.append(arg)
        
        if len(found_args) >= 3:  # At least 3 out of 4 (be lenient)
            reward += 0.10
            feedback_parts.append(f"✅ Task includes required arguments ({len(found_args)}/4: {', '.join(found_args)})")
        elif len(found_args) > 0:
            # Partial credit
            partial = len(found_args) / 4
            reward += 0.10 * partial
            feedback_parts.append(f"⚠️ Task includes some arguments ({len(found_args)}/4: {', '.join(found_args)})")
        else:
            feedback_parts.append("❌ Task missing required arguments (--input, --output, sales_data.csv, report.json)")
        
        # ===== Final Score Calculation =====
        score = int(reward * 100)
        passed = score >= 90  # Need 90% to pass
        
        # Add summary message
        if passed:
            feedback_parts.insert(0, f"🎉 Task successfully created! Score: {score}/100")
        elif score >= 70:
            feedback_parts.insert(0, f"⚠️ Task partially complete. Score: {score}/100 (need 90+)")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete. Score: {score}/100 (need 90+)")
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Score: {score}/100, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": int(reward * 100),
            "feedback": f"❌ Verification error: {str(e)}"
        }
        
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                logger.debug(f"Cleaned up temp directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")
