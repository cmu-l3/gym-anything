#!/usr/bin/env python3
"""
Verifier for create_accounting_math_evaluator task.
Evaluates agent's ability to create proper Talon voice command code
and safely parse accounting math formats in Python.
"""

import json
import os
import tempfile
import logging
import sys
import types
from unittest.mock import MagicMock

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def evaluate_parsing_logic(py_content, test_cases):
    """
    Safely mock the talon environment and run the agent's parse_and_evaluate function.
    """
    if not py_content:
        return 0, "Python file is empty or missing."

    # Mock talon imports to prevent ModuleNotFoundError when exec is called
    mock_talon = types.ModuleType("talon")
    sys.modules["talon"] = mock_talon

    class DummyMod:
        def action_class(self, cls): 
            return cls
        
    mock_talon.Module = DummyMod
    mock_talon.actions = MagicMock()
    mock_talon.clip = MagicMock()
    mock_talon.app = MagicMock()

    local_scope = {}
    try:
        exec(py_content, {}, local_scope)
    except Exception as e:
        return 0, f"Python syntax or execution error: {str(e)}"

    if "parse_and_evaluate" not in local_scope:
        return 0, "Function `parse_and_evaluate` not found in file."

    func = local_scope["parse_and_evaluate"]
    passed_tests = 0
    feedback_notes = []

    for idx, case in enumerate(test_cases):
        expr = case["expr"]
        expected = case["expected"]
        try:
            result = func(expr)
            if str(result) == str(expected):
                passed_tests += 1
            else:
                feedback_notes.append(f"Test {idx+1} failed: eval('{expr}') returned '{result}', expected '{expected}'")
        except Exception as e:
            feedback_notes.append(f"Test {idx+1} raised error: {str(e)}")

    pts = passed_tests * 10
    msg = f"Passed {passed_tests}/{len(test_cases)} parsing tests."
    if feedback_notes:
        msg += " (" + "; ".join(feedback_notes[:2]) + ")"
    return pts, msg

def verify_accounting_math(traj, env_info, task_info):
    """
    Multi-criteria verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    test_cases = metadata.get('test_cases', [
        {"expr": "$(1,200.00) + 500.00", "expected": "-700.00"},
        {"expr": "1,000 * 2.5", "expected": "2500.00"},
        {"expr": "(50.00) - (25.00)", "expected": "-75.00"},
        {"expr": " $ 10,000.50 / 2 ", "expected": "5000.25"}
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use typical Windows root path for Docker user (C:\)
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to fetch task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')

    # 1. File Structure (10 points)
    if result.get('py_exists') and result.get('talon_exists'):
        score += 10
        feedback_parts.append("Both required files exist")
    else:
        feedback_parts.append("Missing required files")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Talon Commands (20 points)
    talon_cmds = [line.strip() for line in talon_content.split('\n') if ':' in line]
    has_replace = any(c.startswith('figure replace:') and 'user.figure_replace()' in c for c in talon_cmds)
    has_append = any(c.startswith('figure append:') and 'user.figure_append()' in c for c in talon_cmds)
    
    if has_replace and has_append:
        score += 20
        feedback_parts.append("Talon commands mapped correctly")
    else:
        feedback_parts.append("Talon commands mapping incorrect or missing")

    # 3. Action Registration (20 points)
    if '@mod.action_class' in py_content and 'def figure_replace' in py_content and 'def figure_append' in py_content:
        score += 20
        feedback_parts.append("Python actions registered properly")
    else:
        feedback_parts.append("Python action registration incomplete")

    # 4. Clipboard Timing (10 points)
    if 'sleep(' in py_content or 'actions.sleep(' in py_content:
        score += 10
        feedback_parts.append("Clipboard delay (sleep) included")
    else:
        feedback_parts.append("Missing sleep/delay for clipboard safety")

    # 5. Parsing Logic (40 points - 10 per unit test)
    parsing_score, parsing_msg = evaluate_parsing_logic(py_content, test_cases)
    score += parsing_score
    feedback_parts.append(parsing_msg)

    # Optional VLM check to prove trajectory work
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, n=3)
    
    if query_vlm and frames:
        prompt = "Did the user open a text editor (Notepad, VSCode, etc.) and write code? Reply JSON `{\"wrote_code\": true/false}`"
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("wrote_code"):
            feedback_parts.append("VLM verified code editor usage")
        else:
            feedback_parts.append("VLM did not observe coding activity")

    passed = (score >= 80 and parsing_score == 40)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }