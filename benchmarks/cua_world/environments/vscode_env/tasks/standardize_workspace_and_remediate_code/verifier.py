#!/usr/bin/env python3
"""
Verifier for the Standardize Workspace and Remediate Code task.

Validates that the required .vscode configurations were created properly
and that the injected Python formatting and linting bugs were resolved.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure the agent interacted via the IDE correctly
VLM_PROMPT = """You are verifying an agent's trajectory in a VS Code environment.
The agent was asked to standardize workspace settings (creating files in a .vscode folder) and remediate Python code using formatters and linters.
Review the provided frames. Did the agent utilize VS Code to create/edit JSON config files OR edit the python files in the workspace?
Provide your response in JSON format:
{
    "used_vscode": true/false,
    "reasoning": "Brief explanation of what the agent was seen doing"
}
"""

def verify_workspace_and_code(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_extensions = metadata.get('expected_extensions', ["ms-python.python", "ms-python.black-formatter", "ms-python.flake8"])
    min_lines = metadata.get('minimum_line_count', 5)

    # 1. Retrieve the exported data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/workspace_result.json", temp_result.name)
        if not os.path.exists(temp_result.name) or os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    files = result.get("files", {})
    lint = result.get("lint_results", {})

    # Criterion 1: settings.json (10 points)
    settings = files.get("settings.json", {})
    if settings.get("exists") and settings.get("is_valid_json"):
        content = settings.get("content", {})
        c1 = content.get("editor.formatOnSave") is True
        c2 = content.get("[python]", {}).get("editor.defaultFormatter") == "ms-python.black-formatter"
        c3 = content.get("python.linting.flake8Enabled") is True
        if c1 and c2 and c3:
            score += 10
            feedback_parts.append("[+] settings.json perfectly configured")
        else:
            feedback_parts.append("[-] settings.json is missing required keys or values")
    else:
        feedback_parts.append("[-] settings.json not created or invalid JSON")

    # Criterion 2: extensions.json (10 points)
    extensions = files.get("extensions.json", {})
    if extensions.get("exists") and extensions.get("is_valid_json"):
        recs = extensions.get("content", {}).get("recommendations", [])
        if all(ext in recs for ext in expected_extensions):
            score += 10
            feedback_parts.append("[+] extensions.json contains required recommendations")
        else:
            feedback_parts.append("[-] extensions.json missing one or more required recommendations")
    else:
        feedback_parts.append("[-] extensions.json not created or invalid JSON")

    # Criterion 3: launch.json (10 points)
    launch = files.get("launch.json", {})
    if launch.get("exists") and launch.get("is_valid_json"):
        configs = launch.get("content", {}).get("configurations", [])
        valid_launch = any(
            c.get("type") == "python" and 
            c.get("request") == "launch" and 
            c.get("module") == "uvicorn" and
            "example:app" in c.get("args", [])
            for c in configs
        )
        if valid_launch:
            score += 10
            feedback_parts.append("[+] launch.json contains correct uvicorn debug target")
        else:
            feedback_parts.append("[-] launch.json missing correct uvicorn configuration")
    else:
        feedback_parts.append("[-] launch.json not created or invalid JSON")

    # Criterion 4: tasks.json (10 points)
    tasks = files.get("tasks.json", {})
    if tasks.get("exists") and tasks.get("is_valid_json"):
        task_list = tasks.get("content", {}).get("tasks", [])
        valid_task = any(
            t.get("type") == "shell" and
            "pytest" in t.get("command", "")
            for t in task_list
        )
        if valid_task:
            score += 10
            feedback_parts.append("[+] tasks.json contains pytest shell task")
        else:
            feedback_parts.append("[-] tasks.json missing correct pytest task")
    else:
        feedback_parts.append("[-] tasks.json not created or invalid JSON")

    # Criterion 5: Code Formatting for applications.py (20 points)
    app_file = files.get("starlette/applications.py", {})
    if app_file.get("exists") and app_file.get("lines", 0) >= min_lines:
        if lint.get("black_exit_code") == 0:
            score += 20
            feedback_parts.append("[+] applications.py formatted perfectly with black")
        else:
            feedback_parts.append("[-] applications.py failed black format check")
    else:
        feedback_parts.append("[-] applications.py deleted or contents emptied (gaming detected)")

    # Criterion 6: Code Linting for routing.py (20 points)
    rout_file = files.get("starlette/routing.py", {})
    if rout_file.get("exists") and rout_file.get("lines", 0) >= min_lines:
        if lint.get("flake8_exit_code") == 0:
            score += 20
            feedback_parts.append("[+] routing.py has 0 flake8 errors")
        else:
            feedback_parts.append("[-] routing.py still has flake8 errors")
    else:
        feedback_parts.append("[-] routing.py deleted or contents emptied (gaming detected)")

    # Criterion 7: VLM Verification of workflow (20 points)
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("used_vscode", False):
                score += 20
                feedback_parts.append("[+] VLM verified genuine VS Code usage")
            else:
                feedback_parts.append("[-] VLM did not observe VS Code usage for editing")
        else:
            feedback_parts.append("[!] VLM query failed")
    else:
        feedback_parts.append("[!] VLM query function unavailable")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }