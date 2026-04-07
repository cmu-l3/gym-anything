#!/usr/bin/env python3
"""
Verifier for create_voice_git_interface task.

Validates the AST/Regex of the generated Talon Python and Talon configuration files
to ensure proper dynamic list assignment, string replacement, and subprocess execution.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_voice_git_interface(traj, env_info, task_info):
    """
    Evaluates the exported Talon Python and `.talon` files.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_created = result.get('py_created_during_task', False)
    talon_created = result.get('talon_created_during_task', False)
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')

    if not (py_exists and talon_exists):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Required files (git_system.py, git_system.talon) not created in target directory."
        }

    if not py_created or not talon_created:
        feedback_parts.append("WARNING: Files were not modified/created during the task execution timeframe.")

    score += 10
    feedback_parts.append("File structure verified (10/10)")

    # 1. Check Python Module/List Declaration
    if re.search(r'mod\.list\s*\(\s*["\']git_branch["\']', py_content) or re.search(r'Module\(\)\.list\s*\(\s*["\']git_branch["\']', py_content):
        score += 10
        feedback_parts.append("List declaration found (10/10)")
    else:
        feedback_parts.append("Missing mod.list('git_branch') declaration")

    # 2. Check Subprocess Execution for git branch
    if "subprocess" in py_content and "git" in py_content and "branch" in py_content:
        score += 20
        feedback_parts.append("Subprocess git branch execution found (20/20)")
    else:
        feedback_parts.append("Missing subprocess execution for 'git branch'")

    # 3. Check Spoken Form Logic (Replacing chars with spaces)
    if ".replace" in py_content or "re.sub" in py_content:
        score += 20
        feedback_parts.append("String replacement logic for spoken forms found (20/20)")
    else:
        feedback_parts.append("Missing string replacement logic to format branch names")

    # 4. Check Context List Update
    if re.search(r'ctx\.lists\s*\[\s*["\'](?:user\.)?git_branch["\']\s*\]\s*=', py_content) or \
       re.search(r'lists\s*\[\s*["\'](?:user\.)?git_branch["\']\s*\]\s*=', py_content) or \
       re.search(r'user\.git_branch', py_content):
        score += 15
        feedback_parts.append("Context list dictionary update found (15/15)")
    else:
        feedback_parts.append("Missing context list update assignment")

    # 5. Dynamic Talon Command checking
    if re.search(r'checkout\s*(?:<user\.text>|\{user\.git_branch\})', talon_content) or \
       re.search(r'\{user\.git_branch\}', talon_content):
        score += 15
        feedback_parts.append("Dynamic {user.git_branch} command trigger found (15/15)")
    else:
        feedback_parts.append("Missing dynamic {user.git_branch} in .talon file")

    # 6. Static Talon Commands checking
    has_status = re.search(r'git status', talon_content)
    has_add = re.search(r'git add', talon_content)
    has_commit = re.search(r'git commit', talon_content)

    if has_status and has_add and has_commit:
        score += 10
        feedback_parts.append("Static git commands found (10/10)")
    elif has_status or has_add or has_commit:
        score += 5
        feedback_parts.append("Partial static git commands found (5/10)")
    else:
        feedback_parts.append("Missing static git commands")

    # Pass threshold is 70, must include subprocess logic and replacement logic
    essential_criteria_met = ("Subprocess git branch execution found (20/20)" in feedback_parts) and \
                             ("String replacement logic for spoken forms found (20/20)" in feedback_parts)
    
    passed = score >= 70 and essential_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }