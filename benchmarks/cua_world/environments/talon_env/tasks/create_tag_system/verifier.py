#!/usr/bin/env python3
"""
Verifier for create_tag_system task.

Validates the architecture of a custom Talon tag system by analyzing AST 
of the Python file and regex parsing of the .talon files.
"""

import os
import json
import tempfile
import ast
import re
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TalonVisitor(ast.NodeVisitor):
    def __init__(self):
        self.has_module = False
        self.tag_declared = False
        self.tag_name = ""
        self.has_context = False
        self.toggle_on_defined = False
        self.toggle_off_defined = False
        
    def visit_Call(self, node):
        # Look for Module() and Context()
        if isinstance(node.func, ast.Name):
            if node.func.id == 'Module':
                self.has_module = True
            elif node.func.id == 'Context':
                self.has_context = True
        # Look for mod.tag(...)
        elif isinstance(node.func, ast.Attribute):
            if node.func.attr == 'tag':
                self.tag_declared = True
                if node.args and isinstance(node.args[0], ast.Constant):
                    self.tag_name = node.args[0].value
        self.generic_visit(node)
        
    def visit_FunctionDef(self, node):
        # Look for toggle action implementations
        name = node.name.lower()
        if 'toggle' in name and 'on' in name:
            self.toggle_on_defined = True
        elif 'toggle' in name and ('off' in name or 'disable' in name):
            self.toggle_off_defined = True
        elif 'presentation' in name and 'on' in name:
            self.toggle_on_defined = True
        elif 'presentation' in name and 'off' in name:
            self.toggle_off_defined = True
        self.generic_visit(node)


def verify_create_tag_system(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read metadata exported by the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get('task_start', 0)
    
    # Check directory
    if result.get('dir_exists'):
        score += 5
        feedback_parts.append("Directory exists (+5)")
    else:
        feedback_parts.append("Directory missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Check presentation_mode.py
    tag_name_py = ""
    if result.get('py_exists'):
        temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env("C:/temp/presentation_mode.py", temp_py.name)
            with open(temp_py.name, 'r') as f:
                py_content = f.read()
                
            try:
                tree = ast.parse(py_content)
                score += 10
                feedback_parts.append("Python syntax valid (+10)")
                
                visitor = TalonVisitor()
                visitor.visit(tree)
                
                if visitor.has_module and visitor.tag_declared:
                    score += 15
                    feedback_parts.append("Module and tag declared (+15)")
                    tag_name_py = visitor.tag_name
                
                if visitor.has_context:
                    score += 5
                    feedback_parts.append("Context created (+5)")
                    
                if visitor.toggle_on_defined:
                    score += 10
                    feedback_parts.append("Toggle-on action defined (+10)")
                    
                if visitor.toggle_off_defined:
                    score += 10
                    feedback_parts.append("Toggle-off action defined (+10)")
                    
            except SyntaxError:
                feedback_parts.append("Python syntax error")
        finally:
            if os.path.exists(temp_py.name):
                os.unlink(temp_py.name)

    # Check presentation_toggle.talon
    if result.get('toggle_exists'):
        temp_toggle = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
        try:
            copy_from_env("C:/temp/presentation_toggle.talon", temp_toggle.name)
            with open(temp_toggle.name, 'r') as f:
                toggle_content = f.read()
                
            has_header = bool(re.search(r'^tag:', toggle_content, re.MULTILINE))
            if not has_header:
                on_exists = re.search(r'presentation\s+mode\s+on', toggle_content, re.IGNORECASE)
                off_exists = re.search(r'presentation\s+mode\s+off', toggle_content, re.IGNORECASE)
                if on_exists and off_exists:
                    score += 10
                    feedback_parts.append("Toggle .talon correct (+10)")
            else:
                feedback_parts.append("Toggle file should not have context header")
        finally:
            if os.path.exists(temp_toggle.name):
                os.unlink(temp_toggle.name)
                
    # Check presentation_commands.talon
    tag_name_talon = ""
    if result.get('cmd_exists'):
        temp_cmd = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
        try:
            copy_from_env("C:/temp/presentation_commands.talon", temp_cmd.name)
            with open(temp_cmd.name, 'r') as f:
                cmd_content = f.read()
                
            header_match = re.search(r'^tag:\s*([^\n]+)\s*\n-', cmd_content, re.MULTILINE)
            if header_match:
                score += 10
                feedback_parts.append("Commands context header present (+10)")
                tag_name_talon = header_match.group(1).strip()
            
            cmds_found = 0
            required_cmds = ['next slide', 'previous slide', 'first slide', 'last slide', 'blank screen', 'start presentation', 'end presentation']
            for cmd in required_cmds:
                if re.search(rf'{cmd}[\s:]', cmd_content, re.IGNORECASE):
                    cmds_found += 1
                    
            if cmds_found >= 5:
                score += 15
                feedback_parts.append(f">=5 presentation commands present (+15)")
            else:
                feedback_parts.append(f"Only {cmds_found}/7 commands found")
        finally:
            if os.path.exists(temp_cmd.name):
                os.unlink(temp_cmd.name)

    # Cross-file consistency logic
    if tag_name_py and tag_name_talon:
        if tag_name_py.replace('user.', '') in tag_name_talon or tag_name_talon.replace('user.', '') in tag_name_py:
            score += 5
            feedback_parts.append("Cross-file tag consistency (+5)")

    # Anti-gaming: Ensure timestamps are after task start
    if result.get('py_mtime', 0) > task_start and result.get('toggle_mtime', 0) > task_start and result.get('cmd_mtime', 0) > task_start:
        score += 5
        feedback_parts.append("Files created during task (+5)")
        
    # Hard requirement criteria check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }