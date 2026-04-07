#!/usr/bin/env python3
"""
Verifier for create_minecraft_voice_controls task.

Checks that the agent properly isolated the commands inside a custom game mode,
utilized the proper stateful hold syntax, mapped Python scripts correctly,
and wrote syntactically valid Talon config files.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_minecraft_voice_controls(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence (10 pts)
    dir_exists = result.get('dir_exists', False)
    py_exists = result.get('python_file_exists', False)
    global_exists = result.get('global_file_exists', False)
    keys_exists = result.get('keys_file_exists', False)
    
    if dir_exists and py_exists and global_exists and keys_exists:
        score += 10
        feedback_parts.append("All files created")
    else:
        feedback_parts.append("Not all files were created")
        if not dir_exists:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Python backend content (20 pts)
    py_content = result.get('python_content', "")
    py_score = 0
    if "Module(" in py_content:
        py_score += 5
    if re.search(r'mode\([\'"]minecraft[\'"]', py_content):
        py_score += 5
    if "mc_stop_all" in py_content:
        py_score += 5
    
    # Check if keys are actually requested to be released
    releases = [r"w:up", r"a:up", r"s:up", r"d:up", r"shift:up", r"space:up"]
    release_count = sum(1 for r in releases if re.search(r, py_content))
    if release_count == 6:
        py_score += 5
    
    score += py_score
    if py_score == 20:
        feedback_parts.append("Python file correct")
    else:
        feedback_parts.append(f"Python file partially correct (score {py_score}/20)")
        
    # 3. Global toggle behavior (20 pts)
    global_content = result.get('global_content', "")
    global_score = 0
    if "minecraft mode enable" in global_content:
        global_score += 5
    if "minecraft mode disable" in global_content:
        global_score += 5
    if re.search(r'mode\.enable\([\'"]user\.minecraft[\'"]\)', global_content):
        global_score += 5
    if re.search(r'mode\.disable\([\'"]user\.minecraft[\'"]\)', global_content):
        global_score += 5
        
    score += global_score
    if global_score == 20:
        feedback_parts.append("Global toggles correct")
    else:
        feedback_parts.append(f"Global toggles partially correct (score {global_score}/20)")

    # 4. Mode-isolated keys file (30 pts)
    keys_content = result.get('keys_content', "")
    keys_score = 0
    
    if re.search(r'mode:\s*user\.minecraft', keys_content):
        score += 10
        feedback_parts.append("Context header correct")
    else:
        feedback_parts.append("Context header missing or incorrect")
        
    if "key(w:down)" in keys_content:
        keys_score += 3
    if "key(s:down)" in keys_content:
        keys_score += 3
    if "key(a:down)" in keys_content:
        keys_score += 3
    if "key(d:down)" in keys_content:
        keys_score += 3
    if "key(shift:down)" in keys_content:
        keys_score += 3
    if "mouse_click(0)" in keys_content or "mouse_click()" in keys_content:
        keys_score += 3
    if "user.mc_stop_all()" in keys_content:
        keys_score += 2
        
    if keys_score >= 15:
        score += 20
        feedback_parts.append("Hold syntax bindings correct")
    else:
        score += keys_score
        feedback_parts.append(f"Hold syntax bindings partially correct (score {keys_score}/20)")

    # 5. Runtime log health (20 pts)
    # Proves the code actually ran without crashing Talon's interpreter
    if not result.get('talon_log_errors', True):
        score += 20
        feedback_parts.append("No Talon syntax errors detected")
    else:
        feedback_parts.append("Talon log shows errors")

    passed = score >= 70 and py_score >= 15 and keys_score >= 15
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }