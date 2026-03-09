#!/usr/bin/env python3
"""
Verifier for debug_broken_talon_setup task.

Four Talon configuration files each contain one error. Scoring:
  - Bug 1 fixed (user_settings.talon: quoted numeric):   25 pts
  - Bug 2 fixed (window_management.talon: missing dash): 25 pts
  - Bug 3 fixed (user.browser_shortcuts.talon-list: list name): 25 pts
  - Bug 4 fixed (text_actions.py: IndentationError):     25 pts
  Total: 100 pts. Pass threshold: 75 (3 of 4 bugs fixed).
"""

import ast
import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_broken_talon_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_path = task_info.get('metadata', {}).get(
        'result_file', 'C:\\Users\\Docker\\debug_broken_talon_setup_result.json'
    )

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(result_path, temp.name)
        with open(temp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.ps1 may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        try:
            os.unlink(temp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Bug 1: user_settings.talon — speech.timeout must not be quoted
    # ------------------------------------------------------------------
    settings_content = result.get('settings_talon', '')
    if not settings_content:
        feedback_parts.append("MISSING user_settings.talon")
    else:
        # The broken form: speech.timeout = "3"  (or any quoted value)
        # Fixed form:      speech.timeout = 3    (bare number, no quotes)
        broken_pattern = re.search(r'speech\.timeout\s*=\s*"', settings_content)
        fixed_pattern  = re.search(r'speech\.timeout\s*=\s*\d', settings_content)
        if not broken_pattern and fixed_pattern:
            score += 25
            feedback_parts.append("PASS Bug1: speech.timeout is correctly a bare number")
        elif broken_pattern:
            feedback_parts.append("FAIL Bug1: speech.timeout still has a quoted string value")
        else:
            feedback_parts.append("FAIL Bug1: speech.timeout line not found in user_settings.talon")

    # ------------------------------------------------------------------
    # Bug 2: window_management.talon — must have a '-' separator line
    # ------------------------------------------------------------------
    window_content = result.get('window_talon', '')
    if not window_content:
        feedback_parts.append("MISSING window_management.talon")
    else:
        lines = window_content.replace('\\n', '\n').splitlines()
        has_separator = any(line.strip() == '-' for line in lines)
        if has_separator:
            score += 25
            feedback_parts.append("PASS Bug2: window_management.talon has '-' separator")
        else:
            feedback_parts.append("FAIL Bug2: window_management.talon missing '-' separator line")

    # ------------------------------------------------------------------
    # Bug 3: user.browser_shortcuts.talon-list — list name must match
    # ------------------------------------------------------------------
    list_content = result.get('list_file', '')
    if not list_content:
        feedback_parts.append("MISSING user.browser_shortcuts.talon-list")
    else:
        lines = list_content.replace('\\n', '\n').splitlines()
        list_header = next((l.strip() for l in lines if l.strip().startswith('list:')), '')
        if list_header == 'list: user.browser_shortcuts':
            score += 25
            feedback_parts.append("PASS Bug3: list name correctly set to user.browser_shortcuts")
        elif list_header == 'list: user.web_shortcuts':
            feedback_parts.append("FAIL Bug3: list name still says user.web_shortcuts (should be user.browser_shortcuts)")
        else:
            feedback_parts.append(f"FAIL Bug3: unexpected list header: '{list_header}'")

    # ------------------------------------------------------------------
    # Bug 4: text_actions.py — must parse without IndentationError
    # ------------------------------------------------------------------
    python_content = result.get('python_file', '')
    if not python_content:
        feedback_parts.append("MISSING text_actions.py")
    else:
        # Unescape \n back to real newlines for ast.parse
        py_source = python_content.replace('\\n', '\n').replace('\\t', '\t')
        try:
            ast.parse(py_source)
            score += 25
            feedback_parts.append("PASS Bug4: text_actions.py is syntactically valid Python")
        except SyntaxError as e:
            feedback_parts.append(f"FAIL Bug4: text_actions.py still has a syntax error: {e}")
        except IndentationError as e:
            feedback_parts.append(f"FAIL Bug4: text_actions.py still has an indentation error: {e}")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
