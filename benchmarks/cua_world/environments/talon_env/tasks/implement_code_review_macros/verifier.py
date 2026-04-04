#!/usr/bin/env python3
"""
Verifier for implement_code_review_macros task.

Scoring breakdown (100 pts total):
  - github_review.talon exists with browser/GitHub context:   20 pts
  - talon file has >= 6 multi-step commands (indented bodies): 25 pts
  - talon file uses sleep() or timing-sensitive patterns:     10 pts
  - github_review.py is syntactically valid Python:           15 pts
  - python file defines >= 4 action methods:                  20 pts
  - python file uses actions.sleep() in >= 2 methods:         10 pts
  Pass threshold: 60 pts.
"""

import ast
import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Code review workflow keywords for context validation
REVIEW_KEYWORDS = [
    'approve', 'comment', 'diff', 'hunk', 'file', 'change', 'review',
    'inline', 'suggest', 'reject', 'merge', 'next', 'previous', 'expand',
    'collapse', 'toggle', 'navigate', 'submit', 'lgtm', 'nitpick', 'tree',
    'sidebar', 'thread', 'resolve', 'request', 'pull', 'pr'
]


def _count_multistep_commands(talon_text):
    """Count commands that have multi-line bodies (indented continuation lines)."""
    lines = talon_text.splitlines()
    in_body = False
    commands = 0
    current_cmd_multiline = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body:
            continue
        if stripped.startswith('#') or not stripped:
            continue
        # Top-level line (command trigger)
        if not line.startswith((' ', '\t')):
            if current_cmd_multiline:
                commands += 1
            current_cmd_multiline = False
            # Check if next non-empty line is indented (multi-step command body)
            for j in range(i + 1, min(i + 10, len(lines))):
                next_line = lines[j]
                if next_line.strip():
                    if next_line.startswith((' ', '\t')):
                        current_cmd_multiline = True
                    break
        # Also count any top-level command (single or multi-line)
    # Handle last command
    if current_cmd_multiline:
        commands += 1
    return commands


def _count_all_commands(talon_text):
    """Count all top-level command trigger lines after the '-' separator."""
    lines = talon_text.splitlines()
    in_body = False
    count = 0
    for line in lines:
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body or stripped.startswith('#') or not stripped:
            continue
        if not line.startswith((' ', '\t')) and ':' in stripped:
            count += 1
    return count


def _has_github_context(talon_text):
    """Check for browser/GitHub context scoping in the talon file."""
    text_lower = talon_text.lower()
    has_browser = bool(re.search(r'app\.name\s*:\s*.*(chrome|firefox|edge|browser)', text_lower))
    has_github  = bool(re.search(r'(github|pull\s*request|url\s*:\s*.*github)', text_lower))
    has_tag     = bool(re.search(r'tag\s*:\s*user\.(github|browser|web)', text_lower))
    return has_browser or has_github or has_tag


def _has_sleep_in_talon(talon_text):
    """Check if the talon file uses sleep() calls in command bodies."""
    return bool(re.search(r'sleep\s*\(', talon_text))


def _count_sleep_usages_in_py(py_source):
    """Count methods that call actions.sleep() or sleep()."""
    try:
        tree = ast.parse(py_source)
    except SyntaxError:
        return 0
    count = 0
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            func_source = ast.dump(node)
            if 'sleep' in func_source:
                count += 1
    return count


def _count_action_methods_in_classes(py_source):
    """Count method definitions inside action class bodies."""
    try:
        tree = ast.parse(py_source)
    except SyntaxError:
        return 0
    count = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    count += 1
    return count


def verify_implement_code_review_macros(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata    = task_info.get('metadata', {})
    result_path = metadata.get('result_file',
                               'C:\\Users\\Docker\\implement_code_review_macros_result.json')
    min_cmds    = metadata.get('min_commands', 6)
    min_actions = metadata.get('min_py_actions', 4)
    min_sleep   = metadata.get('min_sleep_usages', 2)

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp.close()
    try:
        copy_from_env(result_path, temp.name)
        with open(temp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.ps1 may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        try:
            os.unlink(temp.name)
        except OSError:
            pass

    score = 0
    feedback_parts = []

    talon_content = result.get('talon_content', '')
    py_content    = result.get('py_content', '')
    talon_exists  = result.get('talon_file_exists', False)
    py_exists     = result.get('py_file_exists', False)

    talon_text = talon_content.replace('\\n', '\n').replace('\\t', '\t')
    py_text    = py_content.replace('\\n', '\n').replace('\\t', '\t')

    # ------------------------------------------------------------------
    # Criterion 1: github_review.talon exists with GitHub/browser context (20 pts)
    # ------------------------------------------------------------------
    if not talon_exists or not talon_text.strip():
        feedback_parts.append("FAIL C1: github_review.talon not created")
    elif _has_github_context(talon_text):
        score += 20
        feedback_parts.append("PASS C1: talon file has GitHub/browser context scoping")
    else:
        # File exists but no proper context
        score += 8
        feedback_parts.append("PARTIAL C1: github_review.talon exists but lacks GitHub/browser context "
                               "(e.g. app.name: /Chrome/ and url: /github.com/)")

    # ------------------------------------------------------------------
    # Criterion 2: >= 6 commands, majority multi-step (25 pts)
    # ------------------------------------------------------------------
    if talon_text.strip():
        total_cmds    = _count_all_commands(talon_text)
        multistep_cmds = _count_multistep_commands(talon_text)
        logger.info(f"Total commands: {total_cmds}, multi-step: {multistep_cmds}")
        if total_cmds >= min_cmds and multistep_cmds >= 3:
            score += 25
            feedback_parts.append(f"PASS C2: {total_cmds} commands, {multistep_cmds} multi-step")
        elif total_cmds >= min_cmds:
            score += 15
            feedback_parts.append(f"PARTIAL C2: {total_cmds} commands but only "
                                   f"{multistep_cmds} are multi-step (need >= 3)")
        elif total_cmds >= 3:
            score += 8
            feedback_parts.append(f"PARTIAL C2: only {total_cmds} commands (need >= {min_cmds})")
        else:
            feedback_parts.append(f"FAIL C2: only {total_cmds} commands found")
    else:
        feedback_parts.append("FAIL C2: talon file is empty")

    # ------------------------------------------------------------------
    # Criterion 3: talon file uses sleep() for timing (10 pts)
    # ------------------------------------------------------------------
    if talon_text.strip():
        if _has_sleep_in_talon(talon_text):
            score += 10
            feedback_parts.append("PASS C3: talon commands use sleep() for timing")
        else:
            feedback_parts.append("FAIL C3: no sleep() calls in talon command bodies")

    # ------------------------------------------------------------------
    # Criterion 4: github_review.py is valid Python (15 pts)
    # ------------------------------------------------------------------
    if not py_exists or not py_text.strip():
        feedback_parts.append("FAIL C4: github_review.py not created")
    else:
        try:
            ast.parse(py_text)
            score += 15
            feedback_parts.append("PASS C4: github_review.py is syntactically valid Python")
        except SyntaxError as e:
            feedback_parts.append(f"FAIL C4: github_review.py has syntax error: {e}")

    # ------------------------------------------------------------------
    # Criterion 5: >= 4 action methods defined in Python (20 pts)
    # ------------------------------------------------------------------
    if py_text.strip():
        action_count = _count_action_methods_in_classes(py_text)
        logger.info(f"Action method count: {action_count}")
        if action_count >= min_actions:
            score += 20
            feedback_parts.append(f"PASS C5: {action_count} action methods defined")
        elif action_count >= 2:
            score += 10
            feedback_parts.append(f"PARTIAL C5: only {action_count} action methods ({min_actions} required)")
        else:
            feedback_parts.append(f"FAIL C5: only {action_count} action methods ({min_actions} required)")

    # ------------------------------------------------------------------
    # Criterion 6: actions.sleep() used in >= 2 Python methods (10 pts)
    # ------------------------------------------------------------------
    if py_text.strip():
        sleep_count = _count_sleep_usages_in_py(py_text)
        logger.info(f"Sleep usage count: {sleep_count}")
        if sleep_count >= min_sleep:
            score += 10
            feedback_parts.append(f"PASS C6: actions.sleep() used in {sleep_count} Python methods")
        elif sleep_count == 1:
            score += 5
            feedback_parts.append(f"PARTIAL C6: sleep() used in only {sleep_count} method ({min_sleep} required)")
        else:
            feedback_parts.append(f"FAIL C6: no sleep() usage found in Python methods")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
