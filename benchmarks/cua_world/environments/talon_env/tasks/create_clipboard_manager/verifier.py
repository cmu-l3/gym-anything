#!/usr/bin/env python3
"""
Verifier for create_clipboard_manager task.

Verification Strategy:
1. Validates directory and files were created.
2. Parses Python code via AST to verify classes, methods, and Talon decorators.
3. Parses Talon code via regex to verify 8 specific voice commands exist.
4. Validates JSON content matches the pre-loaded real data requirement.
5. VLM check on trajectory to ensure agent actually worked in an editor (anti-gaming).
"""

import json
import os
import tempfile
import logging
import ast
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Required components mapping
REQUIRED_METHODS = {
    'save_clip', 'paste_clip', 'paste_by_index', 'delete_clip', 
    'list_clips', 'search_clips', 'clear_all', 'get_count'
}

REQUIRED_TALON_COMMANDS = [
    r"^clip save <user\.text>:",
    r"^clip paste <user\.text>:",
    r"^clip paste number <number>:",
    r"^clip remove <user\.text>:",
    r"^clip list:",
    r"^clip search <user\.text>:",
    r"^clip clear all:",
    r"^clip count:"
]

VLM_PROMPT = """You are verifying if a computer agent successfully worked on a coding task.
Look at these screenshots from the agent's trajectory.
Did the agent use a text editor or IDE (like Notepad, VSCode, Notepad++, etc.) to write Python code, Talon configuration, or JSON data?
Respond in JSON format:
{
    "used_text_editor": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what the agent is doing in the screenshots"
}"""

def verify_create_clipboard_manager(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keys = metadata.get('expected_json_keys', [])

    score = 0
    feedback_parts = []
    
    # 1. Fetch metadata result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    dir_exists = result.get('target_dir_exists', False)
    if dir_exists:
        score += 5
        feedback_parts.append("Directory created")
    else:
        return {"passed": False, "score": 0, "feedback": "Target directory 'clipboard_manager' was not created."}

    # 2. Verify JSON File Content
    json_exists = result.get('json_exists', False)
    if json_exists:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("C:\\temp\\clipboard_history.json", temp_json.name)
            with open(temp_json.name, 'r', encoding='utf-8') as f:
                history_data = json.load(f)
            
            # Check for the 5 real-data keys
            keys_found = all(k in history_data for k in expected_keys)
            if keys_found:
                score += 15
                feedback_parts.append("JSON pre-loaded correctly")
            else:
                feedback_parts.append("JSON missing required legal boilerplate keys")
        except Exception as e:
            feedback_parts.append(f"JSON parsing error: {e}")
        finally:
            if os.path.exists(temp_json.name):
                os.unlink(temp_json.name)
    else:
        feedback_parts.append("JSON file missing")

    # 3. Verify Python File using AST
    py_exists = result.get('py_exists', False)
    py_valid = False
    if py_exists:
        temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env("C:\\temp\\clipboard_manager.py", temp_py.name)
            with open(temp_py.name, 'r', encoding='utf-8') as f:
                py_code = f.read()
            
            tree = ast.parse(py_code)
            score += 10 # Compiles successfully
            
            # Look for Module instantiation and ClipboardManager class
            has_module = any(isinstance(node, ast.Assign) and isinstance(node.value, ast.Call) 
                             and getattr(node.value.func, 'id', '') == 'Module' for node in ast.walk(tree))
            
            classes = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'ClipboardManager']
            
            if classes:
                score += 5
                cb_class = classes[0]
                
                # Check decorator @mod.action_class
                has_action_decorator = any(getattr(d, 'attr', '') == 'action_class' for d in cb_class.decorator_list)
                if has_action_decorator or has_module:
                    score += 10
                    feedback_parts.append("Talon Module/Action registered")
                
                # Check for required methods
                methods = {m.name for m in cb_class.body if isinstance(m, ast.FunctionDef)}
                found_methods = REQUIRED_METHODS.intersection(methods)
                score += (len(found_methods) * 2) # up to 16 points
                if len(found_methods) == len(REQUIRED_METHODS):
                    score += 4 # Bonus for all methods
                    feedback_parts.append("All Python methods defined")
                else:
                    feedback_parts.append(f"Missing methods: {REQUIRED_METHODS - found_methods}")
                
                # Check for file I/O operations and max limit literal '50'
                if "open(" in py_code or "json.dump" in py_code:
                    score += 5
                if "50" in py_code:
                    score += 5
                if "try:" in py_code and "except" in py_code:
                    score += 5
                
                py_valid = True
        except Exception as e:
            feedback_parts.append(f"Python code issue: {e}")
        finally:
            if os.path.exists(temp_py.name):
                os.unlink(temp_py.name)
    else:
        feedback_parts.append("Python file missing")

    # 4. Verify Talon File using Regex
    talon_exists = result.get('talon_exists', False)
    talon_valid = False
    if talon_exists:
        temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
        try:
            copy_from_env("C:\\temp\\clipboard_manager.talon", temp_talon.name)
            with open(temp_talon.name, 'r', encoding='utf-8') as f:
                talon_lines = f.readlines()
            
            score += 5 # syntax base
            found_commands = 0
            
            for req_cmd in REQUIRED_TALON_COMMANDS:
                if any(re.search(req_cmd, line.strip()) for line in talon_lines):
                    found_commands += 1
            
            score += found_commands # up to 8 points
            if found_commands == len(REQUIRED_TALON_COMMANDS):
                score += 7 # bonus making it 15 total
                feedback_parts.append("All Talon voice commands present")
                talon_valid = True
            else:
                feedback_parts.append(f"Found {found_commands}/{len(REQUIRED_TALON_COMMANDS)} Talon commands")
                
        except Exception as e:
            feedback_parts.append(f"Talon parsing error: {e}")
        finally:
            if os.path.exists(temp_talon.name):
                os.unlink(temp_talon.name)
    else:
        feedback_parts.append("Talon file missing")

    # 5. VLM Trajectory Verification (Anti-Gaming)
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('used_text_editor', False):
                    vlm_passed = True
                    score += 5
                    feedback_parts.append("VLM confirmed editor usage")
                else:
                    feedback_parts.append("VLM did not detect text editor usage")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    else:
        # Give benefit of doubt if VLM unavailable but files match perfectly
        vlm_passed = True

    # Final decision criteria
    # Perfect structure gives around 100 points. We pass at >= 70 assuming files compile and commands exist.
    key_criteria = py_valid and talon_valid and vlm_passed
    passed = score >= 70 and key_criteria

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }