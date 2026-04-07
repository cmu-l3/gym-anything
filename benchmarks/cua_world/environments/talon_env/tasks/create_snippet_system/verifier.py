#!/usr/bin/env python3
"""
Verifier for Create Snippet System task in Talon environment.

Utilizes Python AST parsing to verify code syntax and checks cross-file configuration 
validity ensuring a functional multi-file Talon module was actually produced.
"""

import json
import tempfile
import os
import ast
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_str(node):
    """Helper to safely extract string values across different Python versions."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    elif hasattr(ast, 'Str') and isinstance(node, getattr(ast, 'Str')):
        return node.s
    return None

def verify_create_snippet_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_mappings = metadata.get('required_mappings', {
        "python class": "python_class",
        "python function": "python_function",
        "python try except": "python_try_except",
        "javascript function": "javascript_function",
        "javascript arrow": "javascript_arrow",
        "javascript promise": "javascript_promise",
        "html table": "html_table",
        "html form": "html_form",
        "html boilerplate": "html_boilerplate"
    })

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Pull result dump from the Windows container
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    dir_exists = result.get('dir_exists', False)
    
    # -------------------------------------------------------------
    # 0. Anti-gaming & Directory Check
    # -------------------------------------------------------------
    if dir_exists:
        score += 5
        feedback_parts.append("Directory exists")
    else:
        feedback_parts.append("Directory does not exist")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    files = {f['name']: f for f in result.get('files', [])}
    files_created_after_start = True
    
    for fname in ["snippets.talon-list", "snippets.py", "snippets.talon"]:
        f = files.get(fname, {})
        if not f.get('exists', False):
            feedback_parts.append(f"Missing {fname}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        if f.get('mtime', 0) < task_start:
            files_created_after_start = False
            
    if files_created_after_start:
        score += 5
        feedback_parts.append("Files created within task boundaries")
    else:
        feedback_parts.append("Files created before task start (Anti-gaming)")

    # -------------------------------------------------------------
    # 1. Talon List Validation
    # -------------------------------------------------------------
    list_content = files.get("snippets.talon-list", {}).get("content", "")
    list_lines = [l.strip() for l in list_content.split('\n') if l.strip()]
    
    if list_lines and "list: user.code_snippet" in list_lines[0]:
        score += 5
        feedback_parts.append("List header correct")
    else:
        feedback_parts.append("List header missing/incorrect")
        
    mappings = {}
    for line in list_lines:
        if ":" in line and not line.startswith("list:"):
            parts = line.split(":", 1)
            mappings[parts[0].strip()] = parts[1].strip()
            
    matched_mappings = sum(1 for spoken, identifier in required_mappings.items() 
                           if spoken in mappings and mappings[spoken] == identifier)
            
    if matched_mappings == 9:
        score += 10
        feedback_parts.append("All 9 list mappings present")
    else:
        feedback_parts.append(f"Found {matched_mappings}/9 list mappings")

    # -------------------------------------------------------------
    # 2. Python File AST & Content Validation
    # -------------------------------------------------------------
    py_content = files.get("snippets.py", {}).get("content", "")
    dict_keys = []
    dict_values = []
    
    try:
        tree = ast.parse(py_content)
        score += 5
        feedback_parts.append("Python syntax valid")
        
        has_module = False
        has_dict = False
        
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'Module':
                has_module = True
            elif isinstance(node, ast.Dict):
                if len(node.keys) > len(dict_keys):
                    has_dict = True
                    dict_keys, dict_values = [], []
                    for key, val in zip(node.keys, node.values):
                        k_str = extract_str(key)
                        if k_str is not None:
                            dict_keys.append(k_str)
                            # Extract all string fragments safely inside value node (e.g. inside dedent() wrapper)
                            v_fragments = [extract_str(child) for child in ast.walk(val) if extract_str(child) is not None]
                            dict_values.append(" ".join(v_fragments))
                                
        if has_module:
            score += 10
            feedback_parts.append("Python Module defined")
            
        if has_dict and len(dict_keys) >= 9:
            score += 5
            feedback_parts.append("Python dictionary mapping found")
        else:
            feedback_parts.append(f"Python dictionary incomplete (found {len(dict_keys)} valid keys)")
            
        # Cross file consistency 
        py_snippets = {k: v for k, v in zip(dict_keys, dict_values)}
        if all(identifier in py_snippets for identifier in required_mappings.values()):
            score += 5
            feedback_parts.append("List identifiers match Python keys")
            
        # Code Pattern Validation inside strings
        def check_kws(key, kws):
            text = py_snippets.get(key, "")
            return all(kw in text or (kw == '"""' and "'''" in text) for kw in kws)
            
        py_ok = all([check_kws("python_class", ["class", "__init__", "self"]),
                     check_kws("python_function", ["def", '"""', "return"]),
                     check_kws("python_try_except", ["try", "except", "finally"])])
        if py_ok: score += 10
            
        js_ok = all([check_kws("javascript_function", ["function", "return", "{"]),
                     check_kws("javascript_arrow", ["const", "=>"]),
                     check_kws("javascript_promise", ["Promise", "resolve", "reject"])])
        if js_ok: score += 10
            
        html_ok = all([check_kws("html_table", ["<table", "<tr", "<td"]),
                       check_kws("html_form", ["<form", "action", "<input", "<button"]),
                       check_kws("html_boilerplate", ["DOCTYPE", "<html", "<head", "<body"])])
        if html_ok: score += 10
            
        unique_templates = set(dict_values)
        if len(unique_templates) >= 9:
            score += 5
            feedback_parts.append("Templates are distinct")
            
    except SyntaxError:
        feedback_parts.append("Python syntax INVALID")

    # -------------------------------------------------------------
    # 3. Talon Command Validation
    # -------------------------------------------------------------
    talon_content = files.get("snippets.talon", {}).get("content", "")
    talon_lines = talon_content.split('\n')
    
    if any(cmd in l for l in talon_lines for cmd in ["snippet {user.code_snippet}:", "snippet <user.code_snippet>:"]):
        score += 10
        feedback_parts.append("Snippet insert command present")
        
    if any("snippet list:" in l for l in talon_lines):
        score += 5
        feedback_parts.append("Snippet list command present")

    passed = score >= 60 and dir_exists and files_created_after_start
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }