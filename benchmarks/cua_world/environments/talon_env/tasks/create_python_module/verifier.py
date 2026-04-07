#!/usr/bin/env python3
import json
import os
import tempfile
import ast
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_python_module(traj, env_info, task_info):
    """
    Evaluates the creation of Talon .py and .talon modules using AST analysis.
    Uses 'copy_from_env' safely to extract artifacts across the container boundary.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Read JSON result via copy_from_env
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if result.get('dir_exists'):
        score += 5
        feedback.append("Directory exists")
    else:
        return {"passed": False, "score": 0, "feedback": "case_report directory not found"}

    py_exists = result.get('py_exists')
    talon_exists = result.get('talon_exists')
    
    if not py_exists and not talon_exists:
        return {"passed": False, "score": 5, "feedback": "Files not created"}

    # Anti-gaming timestamp check
    task_start = result.get('task_start', 0)
    py_mtime = result.get('py_mtime', 0)
    
    if py_exists:
        if py_mtime >= task_start:
            score += 5
            feedback.append("Python file created/modified during task")
        else:
            feedback.append("Python file timestamp is before task start (possible gaming)")
            
    if talon_exists:
        score += 5
        feedback.append("Talon file created")

    # 2. Verify Python File Code Logic
    if py_exists:
        temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env("C:\\tmp\\case_report.py", temp_py.name)
            # utf-8-sig ensures any accidental BOM written by Windows editors is correctly ignored
            with open(temp_py.name, 'r', encoding='utf-8-sig') as f:
                py_content = f.read()
                
            # AST Parsing
            try:
                tree = ast.parse(py_content)
                feedback.append("Valid Python syntax")
                
                imports_module = False
                imports_actions = False
                mod_instance = False
                class_has_decorator = False
                class_name_correct = False
                actions_found = set()
                docstrings_count = 0
                
                for node in ast.walk(tree):
                    # Check imports
                    if isinstance(node, ast.ImportFrom) and node.module == 'talon':
                        for alias in node.names:
                            if alias.name == 'Module': imports_module = True
                            if alias.name == 'actions': imports_actions = True
                    
                    # Check mod = Module()
                    if isinstance(node, ast.Assign):
                        for target in node.targets:
                            if isinstance(target, ast.Name) and target.id == 'mod':
                                if isinstance(node.value, ast.Call) and getattr(node.value.func, 'id', '') == 'Module':
                                    mod_instance = True
                                    
                    # Check Class Declaration
                    if isinstance(node, ast.ClassDef):
                        if node.name == 'CaseReportActions':
                            class_name_correct = True
                        for dec in node.decorator_list:
                            if isinstance(dec, ast.Attribute) and getattr(dec.value, 'id', '') == 'mod' and dec.attr == 'action_class':
                                class_has_decorator = True
                                
                        for body_node in node.body:
                            if isinstance(body_node, ast.FunctionDef):
                                func_name = body_node.name
                                if ast.get_docstring(body_node):
                                    docstrings_count += 1
                                    
                                # Map internal actions calls
                                for b_node in ast.walk(body_node):
                                    if isinstance(b_node, ast.Call):
                                        if isinstance(b_node.func, ast.Attribute) and getattr(b_node.func.value, 'id', '') == 'actions' and b_node.func.attr == 'insert':
                                            if func_name in ['insert_evidence_divider', 'insert_chain_of_custody', 'insert_case_closed']:
                                                actions_found.add(func_name)
                                                
                # Score python features based on the README criteria specification
                if imports_module and imports_actions:
                    score += 10
                    feedback.append("Correct imports")
                if mod_instance:
                    score += 10
                    feedback.append("Module instantiated")
                if class_name_correct:
                    score += 5
                    feedback.append("Class name correct")
                if class_has_decorator:
                    score += 10
                    feedback.append("Class decorated correctly")
                    
                if 'insert_evidence_divider' in actions_found:
                    if '========== EVIDENCE ITEM ==========' in py_content:
                        score += 10
                        feedback.append("Evidence divider action found")
                
                if 'insert_chain_of_custody' in actions_found:
                    if 'CHAIN OF CUSTODY' in py_content and 'Condition on Receipt:' in py_content:
                        score += 10
                        feedback.append("Chain of custody action found")
                        
                if 'insert_case_closed' in actions_found:
                    if '[CASE STATUS: CLOSED]' in py_content:
                        score += 10
                        feedback.append("Case closed action found")
                        
                if docstrings_count >= 3:
                    score += 5
                    feedback.append("Docstrings present")
                    
            except SyntaxError as e:
                feedback.append(f"Python syntax error: {e}")
                
        finally:
            if os.path.exists(temp_py.name):
                os.unlink(temp_py.name)

    # 3. Verify Talon Voice Configuration File
    if talon_exists:
        temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
        try:
            copy_from_env("C:\\tmp\\case_report.talon", temp_talon.name)
            with open(temp_talon.name, 'r', encoding='utf-8-sig') as f:
                talon_content = f.read()
                
            if 'evidence divider' in talon_content and 'user.insert_evidence_divider()' in talon_content:
                score += 5
                feedback.append("Talon: evidence divider command")
            if 'chain of custody' in talon_content and 'user.insert_chain_of_custody()' in talon_content:
                score += 5
                feedback.append("Talon: chain of custody command")
            if 'case closed stamp' in talon_content and 'user.insert_case_closed()' in talon_content:
                score += 5
                feedback.append("Talon: case closed stamp command")
                
        finally:
            if os.path.exists(temp_talon.name):
                os.unlink(temp_talon.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }