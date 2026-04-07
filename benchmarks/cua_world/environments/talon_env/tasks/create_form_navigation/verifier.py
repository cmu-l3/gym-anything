#!/usr/bin/env python3
"""
Verifier for create_form_navigation task.
Evaluates the existence, syntactic correctness, and logic completeness of a 4-file Talon configuration.
"""

import os
import json
import re
import ast
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TalonFormatterVisitor(ast.NodeVisitor):
    def __init__(self):
        self.has_module = False
        self.has_action_class = False
        self.imports_talon = False
        self.functions = {}

    def visit_ImportFrom(self, node):
        if node.module == 'talon':
            self.imports_talon = True
        self.generic_visit(node)

    def visit_Import(self, node):
        for alias in node.names:
            if alias.name == 'talon':
                self.imports_talon = True
        self.generic_visit(node)

    def visit_Call(self, node):
        if isinstance(node.func, ast.Name) and node.func.id == 'Module':
            self.has_module = True
        self.generic_visit(node)

    def visit_ClassDef(self, node):
        for dec in node.decorator_list:
            if isinstance(dec, ast.Attribute) and dec.attr == 'action_class':
                self.has_action_class = True
            elif isinstance(dec, ast.Name) and dec.id == 'action_class':
                self.has_action_class = True
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        body_len = len(node.body)
        is_trivial = False
        if body_len == 1:
            stmt = node.body[0]
            if isinstance(stmt, ast.Pass):
                is_trivial = True
            elif isinstance(stmt, ast.Return) and stmt.value is None:
                is_trivial = True
            elif isinstance(stmt, ast.Return) and isinstance(stmt.value, ast.Name):
                is_trivial = True

        self.functions[node.name] = {
            "trivial": is_trivial,
            "body_len": body_len
        }
        self.generic_visit(node)


def check_command_in_talon(content, command_prefix):
    """Check if a specific voice command prefix exists in a .talon file."""
    pattern = r"^\s*" + re.escape(command_prefix) + r"\s*:"
    return bool(re.search(pattern, content, re.MULTILINE | re.IGNORECASE))


def verify_create_form_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)
    files = result.get('files', {})

    metadata = task_info.get('metadata', {})
    req_nav = metadata.get('required_nav_commands', [])
    req_list = metadata.get('required_list_fields', [])
    req_actions = metadata.get('required_py_actions', [])

    # 1. Directory Check (2 pts)
    if result.get('dir_exists'):
        score += 2
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("Directory missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Helper to check if file was made during task
    def is_valid_file(f_data):
        return f_data.get('exists') and f_data.get('mtime', 0) >= task_start

    # 2. form_nav.talon Check
    f_nav = files.get('form_nav.talon', {})
    if is_valid_file(f_nav):
        content = f_nav.get('content', '')
        if len(content.splitlines()) > 5:
            score += 5
            nav_cmds_found = sum(1 for cmd in req_nav if check_command_in_talon(content, cmd))
            score += (nav_cmds_found * 2) # up to 16
            feedback_parts.append(f"form_nav.talon valid ({nav_cmds_found}/{len(req_nav)} cmds)")
        else:
            feedback_parts.append("form_nav.talon too short/empty")
    else:
        feedback_parts.append("form_nav.talon missing or stale")

    # 3. form_fields.talon-list Check
    f_list = files.get('form_fields.talon-list', {})
    list_defined_properly = False
    if is_valid_file(f_list):
        content = f_list.get('content', '')
        if re.search(r"list:\s*user\.form_field_name", content, re.IGNORECASE):
            score += 5
            list_defined_properly = True
            
            # Count mappings
            lines = [l.strip() for l in content.splitlines() if l.strip() and not l.strip().startswith('#') and not l.strip().startswith('list:') and not l.strip().startswith('-')]
            found_reqs = sum(1 for req in req_list if any(l.lower().startswith(req.lower() + ":") for l in lines))
            score += found_reqs # up to 10
            feedback_parts.append(f"form_fields.talon-list valid ({found_reqs}/{len(req_list)} mappings)")
        else:
            feedback_parts.append("form_fields.talon-list missing list header")
    else:
        feedback_parts.append("form_fields.talon-list missing or stale")

    # 4. formatters.py Check
    f_py = files.get('formatters.py', {})
    py_actions_defined = []
    if is_valid_file(f_py):
        content = f_py.get('content', '')
        try:
            tree = ast.parse(content)
            score += 5
            
            visitor = TalonFormatterVisitor()
            visitor.visit(tree)
            
            if visitor.imports_talon:
                score += 3
            if visitor.has_module and visitor.has_action_class:
                score += 5
                
            for act in req_actions:
                if act in visitor.functions and not visitor.functions[act]['trivial']:
                    score += 7 # up to 21
                    py_actions_defined.append(act)
            
            feedback_parts.append(f"formatters.py valid ({len(py_actions_defined)}/3 robust actions)")
        except SyntaxError:
            feedback_parts.append("formatters.py has syntax errors")
    else:
        feedback_parts.append("formatters.py missing or stale")

    # 5. data_entry.talon Check
    f_data = files.get('data_entry.talon', {})
    if is_valid_file(f_data):
        content = f_data.get('content', '')
        score += 5
        
        # Check if calls formatters
        calls_formatters = 0
        for act in req_actions:
            if act in content:
                calls_formatters += 1
        if calls_formatters == 3:
            score += 8
        elif calls_formatters > 0:
            score += (calls_formatters * 2)
            
        # Check status command
        if re.search(r"enter status\s*<user\.", content, re.IGNORECASE):
            score += 5
            
        feedback_parts.append("data_entry.talon valid")
    else:
        feedback_parts.append("data_entry.talon missing or stale")

    # 6. Cross-File Consistency Checks
    # Check if .talon files use the list we defined
    if list_defined_properly:
        if (is_valid_file(f_nav) and 'user.form_field_name' in f_nav.get('content', '')) or \
           (is_valid_file(f_data) and 'user.form_field_name' in f_data.get('content', '')):
            score += 5
            
    # Check if .talon files call the python actions we defined
    if len(py_actions_defined) == 3:
        if is_valid_file(f_data) and all(act in f_data.get('content', '') for act in req_actions):
            score += 5

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }