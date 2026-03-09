#!/usr/bin/env python3
"""
Verifier for create_delegated_command task.

Checks:
1. User 'acmecorp' has 'custom' module enabled in Webmin ACL.
2. A Custom Command exists that executes 'systemctl restart acmecorp-worker'.
3. That command is configured to run as 'root'.
4. That command is assigned to user 'acmecorp'.
"""

import json
import os
import sys
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_delegated_command(traj, env_info, task_info):
    """
    Verify the agent created the correct custom command and assigned permissions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    target_user = "acmecorp"
    target_cmd = "systemctl restart acmecorp-worker"

    # ----------------------------------------------------------------
    # Check 1: Module Access (30 points)
    # ----------------------------------------------------------------
    acl_b64 = result.get("acl_content_base64", "")
    has_module = False
    
    if acl_b64:
        try:
            acl_content = base64.b64decode(acl_b64).decode('utf-8')
            for line in acl_content.splitlines():
                # Line format: username: module1 module2 ...
                parts = line.strip().split(':')
                if parts[0] == target_user:
                    modules = parts[1].split() if len(parts) > 1 else []
                    if "custom" in modules:
                        has_module = True
                        break
        except Exception as e:
            feedback.append(f"Error parsing ACL: {e}")

    if has_module:
        score += 30
        feedback.append(f"Pass: User '{target_user}' has access to 'Custom Commands' module.")
    else:
        feedback.append(f"Fail: User '{target_user}' does NOT have access to 'Custom Commands' module.")

    # ----------------------------------------------------------------
    # Check 2, 3, 4: Command Configuration (70 points)
    # ----------------------------------------------------------------
    config_b64 = result.get("custom_config_content_base64", "")
    cmd_found = False
    cmd_correct_user = False
    cmd_assigned = False

    if config_b64:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8')
            config = {}
            for line in config_content.splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    config[k.strip()] = v.strip()

            # Find the command index
            # Look for command_X = systemctl restart acmecorp-worker
            # Note: The user might have typed it with extra spaces, so we check broadly
            found_idx = -1
            for k, v in config.items():
                if k.startswith("command_") and target_cmd in v:
                    found_idx = k.split("_")[1]
                    cmd_found = True
                    break
            
            if cmd_found:
                score += 30
                feedback.append(f"Pass: Custom command created matching '{target_cmd}'.")

                # Check 3: Run as root
                # Key: user_X (singular) is the execution user
                exec_user = config.get(f"user_{found_idx}", "root") # Default is usually root if not set, but let's check explicit
                if exec_user == "root":
                    score += 20
                    cmd_correct_user = True
                    feedback.append("Pass: Command runs as root.")
                else:
                    feedback.append(f"Fail: Command runs as '{exec_user}', expected 'root'.")

                # Check 4: Assigned to user
                # Key: users_X (plural) is the list of users who can use it
                assigned_users = config.get(f"users_{found_idx}", "").split()
                if target_user in assigned_users:
                    score += 20
                    cmd_assigned = True
                    feedback.append(f"Pass: Command assigned to user '{target_user}'.")
                else:
                    feedback.append(f"Fail: Command NOT assigned to '{target_user}'. Assigned to: {assigned_users}")

            else:
                feedback.append(f"Fail: No custom command found executing '{target_cmd}'.")

        except Exception as e:
            feedback.append(f"Error parsing custom config: {e}")
    else:
        feedback.append("Fail: Custom commands configuration file empty or missing.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = (score >= 80) # Needs mostly everything correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }