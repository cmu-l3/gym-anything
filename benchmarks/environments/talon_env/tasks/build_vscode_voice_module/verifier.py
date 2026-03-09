#!/usr/bin/env python3
"""
Verifier for build_vscode_voice_module task.

Scoring breakdown (100 pts total):
  - vscode.talon exists and has VS Code context header:      20 pts
  - vscode.talon has >= 10 voice command definitions:        25 pts
  - vscode.talon has commands spanning >= 2 categories
    (navigation/editing/search/debug etc.):                  15 pts
  - vscode.py exists and is syntactically valid Python:      20 pts
  - vscode.py defines >= 3 action methods in action class:   20 pts
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

# Keywords that suggest different command categories
NAVIGATION_KEYWORDS = ['go', 'line', 'jump', 'scroll', 'next', 'previous', 'top', 'bottom',
                       'file', 'back', 'forward', 'end', 'start', 'begin']
EDITING_KEYWORDS    = ['select', 'delete', 'copy', 'paste', 'cut', 'undo', 'redo', 'insert',
                       'duplicate', 'wrap', 'indent', 'format', 'rename', 'replace']
SEARCH_KEYWORDS     = ['find', 'search', 'grep', 'symbol', 'reference', 'open', 'recent']
CODE_KEYWORDS       = ['run', 'debug', 'build', 'test', 'comment', 'fold', 'expand',
                       'terminal', 'panel', 'sidebar', 'split', 'close']


def _count_command_lines(talon_text):
    """Count lines that look like voice command definitions (contain ': ' pattern)."""
    lines = talon_text.splitlines()
    in_body = False
    command_count = 0
    for line in lines:
        stripped = line.strip()
        if stripped == '-':
            in_body = True
            continue
        if not in_body:
            continue
        # A command line: text followed by ': ' and an action, at top indent level
        # Skip lines that are continuations (indented) or blank or comment
        if stripped.startswith('#') or not stripped:
            continue
        # Top-level command: not indented (or lightly indented as trigger phrase)
        # Pattern: "phrase: action" OR "phrase:" (multi-line)
        if not line.startswith(' ') and not line.startswith('\t') and ':' in stripped:
            command_count += 1
    return command_count


def _has_vscode_context(talon_text):
    """Check that the file has a VS Code application context header."""
    text_lower = talon_text.lower()
    # Must have app.name or app reference to vscode/visual studio code
    # and NOT have an unconditional (no context) header
    has_app_context = bool(re.search(
        r'app\.name\s*:\s*.*(code|vscode|visual studio)',
        text_lower
    ))
    has_tag_or_mode = bool(re.search(r'tag\s*:\s*user\.vscode', text_lower))
    return has_app_context or has_tag_or_mode


def _count_categories(talon_text):
    """Estimate how many command categories the file covers."""
    text_lower = talon_text.lower()
    categories_found = 0
    for kw_list in [NAVIGATION_KEYWORDS, EDITING_KEYWORDS, SEARCH_KEYWORDS, CODE_KEYWORDS]:
        if any(kw in text_lower for kw in kw_list):
            categories_found += 1
    return categories_found


def _count_action_methods(py_source):
    """Count action method definitions inside @mod.action_class or @ctx.action classes."""
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


def verify_build_vscode_voice_module(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata    = task_info.get('metadata', {})
    result_path = metadata.get('result_file', 'C:\\Users\\Docker\\build_vscode_voice_module_result.json')
    min_cmds    = metadata.get('min_commands', 10)
    min_actions = metadata.get('min_py_actions', 3)

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

    # Unescape \n sequences written by PowerShell export
    talon_text = talon_content.replace('\\n', '\n').replace('\\t', '\t')
    py_text    = py_content.replace('\\n', '\n').replace('\\t', '\t')

    # ------------------------------------------------------------------
    # Criterion 1: vscode.talon exists with VS Code context header (20 pts)
    # ------------------------------------------------------------------
    if not talon_exists or not talon_text.strip():
        feedback_parts.append("FAIL C1: vscode.talon not created")
    elif _has_vscode_context(talon_text):
        score += 20
        feedback_parts.append("PASS C1: vscode.talon has VS Code context header")
    else:
        # Give partial credit if file exists but context is wrong
        score += 10
        feedback_parts.append("PARTIAL C1: vscode.talon exists but missing app context restriction "
                               "(e.g. app.name: /Code/)")

    # ------------------------------------------------------------------
    # Criterion 2: >= 10 voice commands (25 pts)
    # ------------------------------------------------------------------
    if talon_text.strip():
        cmd_count = _count_command_lines(talon_text)
        logger.info(f"Command count: {cmd_count}")
        if cmd_count >= min_cmds:
            score += 25
            feedback_parts.append(f"PASS C2: {cmd_count} voice commands found (>= {min_cmds} required)")
        elif cmd_count >= 5:
            score += 12
            feedback_parts.append(f"PARTIAL C2: only {cmd_count} commands found ({min_cmds} required)")
        else:
            feedback_parts.append(f"FAIL C2: only {cmd_count} commands found ({min_cmds} required)")
    else:
        feedback_parts.append("FAIL C2: vscode.talon is empty")

    # ------------------------------------------------------------------
    # Criterion 3: >= 2 command categories (15 pts)
    # ------------------------------------------------------------------
    if talon_text.strip():
        cats = _count_categories(talon_text)
        if cats >= 2:
            score += 15
            feedback_parts.append(f"PASS C3: commands span {cats} categories")
        else:
            feedback_parts.append(f"FAIL C3: commands cover only {cats} category (need >= 2)")
    else:
        feedback_parts.append("FAIL C3: vscode.talon is empty")

    # ------------------------------------------------------------------
    # Criterion 4: vscode.py exists and is valid Python (20 pts)
    # ------------------------------------------------------------------
    if not py_exists or not py_text.strip():
        feedback_parts.append("FAIL C4: vscode.py not created")
    else:
        try:
            ast.parse(py_text)
            score += 20
            feedback_parts.append("PASS C4: vscode.py is syntactically valid Python")
        except SyntaxError as e:
            feedback_parts.append(f"FAIL C4: vscode.py has a syntax error: {e}")

    # ------------------------------------------------------------------
    # Criterion 5: vscode.py defines >= 3 action methods (20 pts)
    # ------------------------------------------------------------------
    if py_text.strip():
        action_count = _count_action_methods(py_text)
        logger.info(f"Action method count: {action_count}")
        if action_count >= min_actions:
            score += 20
            feedback_parts.append(f"PASS C5: {action_count} action methods defined (>= {min_actions} required)")
        elif action_count >= 1:
            score += 10
            feedback_parts.append(f"PARTIAL C5: only {action_count} action methods ({min_actions} required)")
        else:
            feedback_parts.append("FAIL C5: no action methods found in vscode.py")
    else:
        feedback_parts.append("FAIL C5: vscode.py is empty")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
