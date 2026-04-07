#!/usr/bin/env python3
"""
Verifier for create_cross_app_macro task.
Analyzes the Python AST and Talon configuration files to verify the agent accurately
implemented the required logic without executing unsafe dynamic tests.
"""

import json
import os
import tempfile
import logging
import ast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_ast_for_macro(code_str):
    """
    Parses the agent's Python code and traverses the AST to check for required
    cross-application automation structures.
    """
    try:
        tree = ast.parse(code_str)
    except SyntaxError:
        return {"valid_syntax": False}

    features = {
        "valid_syntax": True,
        "has_module_class": False,
        "has_active_app": False,
        "has_apps_loop": False,
        "has_notepad_check": False,
        "has_focus_call": False,
        "has_sleep_call": False,
        "has_copy_call": False,
        "has_paste_call": False,
        "has_enter_call": False,
        "has_insert_call": False
    }

    for node in ast.walk(tree):
        # 1. Check decorators for @mod.action_class
        if isinstance(node, ast.ClassDef):
            for dec in node.decorator_list:
                if isinstance(dec, ast.Attribute) and dec.attr == 'action_class':
                    features["has_module_class"] = True

        # 2. Check function calls
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute):
                if func.attr == 'active_app':
                    features["has_active_app"] = True
                elif func.attr == 'apps':
                    features["has_apps_loop"] = True
                elif func.attr == 'focus':
                    features["has_focus_call"] = True
                elif func.attr == 'sleep':
                    features["has_sleep_call"] = True
                elif func.attr == 'insert':
                    features["has_insert_call"] = True
                elif func.attr == 'paste':
                    features["has_paste_call"] = True
                elif func.attr == 'key':
                    if node.args and isinstance(node.args[0], ast.Constant):
                        val = str(node.args[0].value).lower()
                        if 'ctrl-c' in val:
                            features["has_copy_call"] = True
                        if 'ctrl-v' in val:
                            features["has_paste_call"] = True
                        if 'enter' in val:
                            features["has_enter_call"] = True

        # 3. Check strings/constants for Notepad target
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            if node.value.lower() == 'notepad':
                features["has_notepad_check"] = True

    return features


def verify_create_cross_app_macro(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Pull result JSON directly from Windows temp dir
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_content = result.get('py_content', "")
    talon_content = result.get('talon_content', "")
    
    task_start = result.get('task_start', 0)
    py_mtime = result.get('py_mtime', 0)
    talon_mtime = result.get('talon_mtime', 0)

    # -------------------------------------------------------------
    # CRITERION 1: File Existence & Anti-Gaming Timestamps (20 pts)
    # -------------------------------------------------------------
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("Both configuration files exist")
        
        # Verify files were created/modified during the actual task 
        if py_mtime >= task_start and talon_mtime >= task_start:
            score += 10
            feedback_parts.append("Files correctly created during task window")
        else:
            feedback_parts.append("Warning: Files appear to pre-date the task start")
    else:
        if not py_exists: feedback_parts.append("Missing evidence_macro.py")
        if not talon_exists: feedback_parts.append("Missing evidence.talon")
        return {"passed": False, "score": score, "feedback": ", ".join(feedback_parts)}

    # -------------------------------------------------------------
    # CRITERION 2: Python Action AST Logic (60 pts)
    # -------------------------------------------------------------
    ast_features = check_ast_for_macro(py_content)
    
    if not ast_features["valid_syntax"]:
        feedback_parts.append("Python file has invalid syntax")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    score += 10
    feedback_parts.append("Python syntax is valid")
    
    # Assess presence of core UI logic components
    ast_score = 0
    if ast_features["has_module_class"]: ast_score += 5
    if ast_features["has_active_app"]: ast_score += 5
    if ast_features["has_apps_loop"]: ast_score += 5
    if ast_features["has_notepad_check"]: ast_score += 5
    if ast_features["has_focus_call"]: ast_score += 5
    if ast_features["has_sleep_call"]: ast_score += 5
    if ast_features["has_copy_call"]: ast_score += 5
    if ast_features["has_paste_call"]: ast_score += 5
    if ast_features["has_enter_call"]: ast_score += 5
    if ast_features["has_insert_call"]: ast_score += 5
    
    score += ast_score
    feedback_parts.append(f"AST Application Logic Score: {ast_score}/50")

    # -------------------------------------------------------------
    # CRITERION 3: Talon Voice Binding (10 pts)
    # -------------------------------------------------------------
    talon_valid = False
    talon_lower = talon_content.lower()
    if "log evidence" in talon_lower and "<user.text>" in talon_lower:
        if "user.log_evidence(" in talon_content:
            talon_valid = True
            score += 10
            feedback_parts.append("Talon file properly binds voice command to action")
        else:
            feedback_parts.append("Talon command is missing the call to user.log_evidence()")
    else:
        feedback_parts.append("Talon file missing 'log evidence <user.text>' rule")

    # -------------------------------------------------------------
    # CRITERION 4: VLM Trajectory Process Verification (10 pts)
    # -------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = "Did the user utilize an editor to author and write python/talon files for a macro? Answer 'yes' or 'no'."
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get("success") and 'yes' in vlm_res.get("response", "").lower():
                    score += 10
                    feedback_parts.append("VLM verified workflow trajectory")
                else:
                    feedback_parts.append("VLM did not clearly verify workflow process")
        except Exception as e:
            logger.warning(f"VLM verification skipped: {e}")

    # Minimum threshold to pass is robust logic structure + valid talon wiring
    passed = score >= 80 and talon_valid and ast_score >= 40
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }