#!/usr/bin/env python3
"""
Verifier for create_powershell_voice task.

Verification Strategy:
1. Programmatic Checks (Primary):
   - Validates existence and timestamps of all 3 required files
   - Uses AST parsing on Python to ensure methods, subprocess.run, try/except, and app.notify exist
   - Uses textual matching for `.talon` mapping
   - Counts items in `.talon-list`
2. VLM Verification (Secondary):
   - Uses trajectory frames to confirm an editor was used and workflow completed
"""

import os
import json
import ast
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TalonASTVisitor(ast.NodeVisitor):
    def __init__(self):
        self.methods = set()
        self.has_subprocess = False
        self.has_try = False
        self.has_notify = False
        self.writes_to_expected_path = False

    def visit_FunctionDef(self, node):
        self.methods.add(node.name)
        self.generic_visit(node)

    def visit_Call(self, node):
        # Check for subprocess.run
        if isinstance(node.func, ast.Attribute):
            if getattr(node.func.value, 'id', '') == 'subprocess' and node.func.attr == 'run':
                self.has_subprocess = True
            # Check actions.app.notify()
            if getattr(node.func.value, 'id', '') == 'app' and node.func.attr == 'notify':
                self.has_notify = True
            if getattr(node.func.value, 'attr', '') == 'app' and node.func.attr == 'notify':
                self.has_notify = True
        
        if isinstance(node.func, ast.Attribute) and node.func.attr == 'notify':
            self.has_notify = True
            
        self.generic_visit(node)

    def visit_Try(self, node):
        self.has_try = True
        self.generic_visit(node)

    def visit_Constant(self, node):
        if isinstance(node.value, str):
            if 'talon_shell_output.txt' in node.value:
                self.writes_to_expected_path = True
        self.generic_visit(node)


def verify_create_powershell_voice(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_methods = set(metadata.get('required_methods', []))

    score = 0
    feedback_parts = []
    
    # Copy results from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files = result.get('files', {})
    task_start = result.get('task_start', 0)

    # Criterion 1: Directory exists (5 points)
    if result.get('dir_exists'):
        score += 5
        feedback_parts.append("Integration directory created")
    else:
        feedback_parts.append("Directory missing")

    # Criterion 2 & 3: Python file parsing (up to 40 points)
    py_file = files.get('powershell_commands.py', {})
    if py_file.get('exists'):
        if py_file.get('mtime', 0) >= task_start:
            score += 5  # Anti-gaming: modified during task
            
        py_content = py_file.get('content', '')
        try:
            tree = ast.parse(py_content)
            visitor = TalonASTVisitor()
            visitor.visit(tree)
            
            score += 5 # Syntactically valid
            
            # Check methods
            found_methods = required_methods.intersection(visitor.methods)
            if len(found_methods) == len(required_methods):
                score += 10
                feedback_parts.append("All Python actions defined")
            else:
                feedback_parts.append(f"Missing actions: {required_methods - visitor.methods}")
                
            if visitor.has_subprocess:
                score += 5
            if visitor.has_try:
                score += 5
            if visitor.has_notify:
                score += 5
            if visitor.writes_to_expected_path:
                score += 5
                
        except SyntaxError as e:
            feedback_parts.append(f"Python syntax error: {e}")
    else:
        feedback_parts.append("Missing .py file")

    # Criterion 4: Talon file validation (20 points)
    talon_file = files.get('powershell_commands.talon', {})
    if talon_file.get('exists'):
        if talon_file.get('mtime', 0) >= task_start:
            score += 5
            
        talon_content = talon_file.get('content', '')
        mappings = [
            "shell list processes", "shell disk space", 
            "shell network test", "shell event log"
        ]
        mappings_found = sum(1 for m in mappings if m in talon_content)
        
        if mappings_found >= 4:
            score += 15
            feedback_parts.append("Talon phrases mapped correctly")
        else:
            feedback_parts.append(f"Talon commands incomplete ({mappings_found}/4 core mappings)")
    else:
        feedback_parts.append("Missing .talon file")

    # Criterion 5: Talon List validation (15 points)
    list_file = files.get('powershell_services.talon-list', {})
    if list_file.get('exists'):
        if list_file.get('mtime', 0) >= task_start:
            score += 5
            
        list_content = list_file.get('content', '')
        if 'list: user.ps_cmdlet' in list_content:
            score += 5
            
        # Count entries (lines with colons that aren't comments or headers)
        valid_entries = 0
        for line in list_content.split('\n'):
            line = line.strip()
            if line and not line.startswith('#') and ':' in line and not line.startswith('list:'):
                valid_entries += 1
                
        if valid_entries >= 15:
            score += 5
            feedback_parts.append(f"List file has {valid_entries} entries")
        else:
            feedback_parts.append(f"List file has only {valid_entries} entries (needs 15)")
    else:
        feedback_parts.append("Missing .talon-list file")

    # Criterion 6: VLM Trajectory (20 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these trajectory screenshots of an agent performing a task on a Windows environment.
        The goal was to create three Talon voice configuration files (.py, .talon, .talon-list) in a text editor to interact with PowerShell.
        Did the agent successfully open a text editor (e.g. Notepad, VS Code), type out the python code/configuration, and save the files in the APPDATA roaming folder?
        Respond in JSON with 'workflow_completed' (boolean).
        """
        
        vlm_result = query_vlm(images=frames + [final] if final else frames, prompt=prompt)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("workflow_completed"):
                score += 20
                feedback_parts.append("VLM confirmed text editing workflow")
            else:
                feedback_parts.append("VLM found workflow incomplete")
                
    passed = score >= 65 and py_file.get('exists', False) and 'Python syntax error' not in "".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }