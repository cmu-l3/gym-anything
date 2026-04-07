#!/usr/bin/env python3
"""
Verifier for create_entity_mapper task.

Verifies the creation of a 4-file Talon module for graph database mapping via static analysis.
Checks file presence, list definitions, Python AST structures, and voice command mappings.
"""

import json
import os
import tempfile
import zipfile
import ast
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_entity_mapper(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp()
    json_path = os.path.join(temp_dir, 'task_result.json')
    zip_path = os.path.join(temp_dir, 'intel_mapper.zip')
    
    try:
        # Retrieve result metadata
        copy_from_env("C:\\task_result.json", json_path)
        with open(json_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
            
        if not result.get('directory_created', False):
            return {"passed": False, "score": 0, "feedback": "intel_mapper directory was not created."}
            
        if result.get('file_count', 0) == 0:
            return {"passed": False, "score": 0, "feedback": "Directory created but no files found."}

        # Retrieve and extract zip
        copy_from_env("C:\\intel_mapper.zip", zip_path)
        extract_dir = os.path.join(temp_dir, 'extracted')
        os.makedirs(extract_dir, exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        files_found = os.listdir(extract_dir)
        
        # Criterion 1: File Structure (10 points)
        required_files = [
            'entity_types.talon-list',
            'relationship_types.talon-list',
            'intel_mapper.py',
            'intel_mapper.talon'
        ]
        
        missing_files = [f for f in required_files if f not in files_found]
        if not missing_files:
            score += 10
            feedback_parts.append("All 4 files created successfully.")
        else:
            feedback_parts.append(f"Missing files: {', '.join(missing_files)}.")

        # Helper to read files robustly
        def read_file(name):
            path = os.path.join(extract_dir, name)
            if not os.path.exists(path):
                return ""
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return f.read()
            except UnicodeDecodeError:
                with open(path, 'r', encoding='utf-16') as f:
                    return f.read()

        # Criterion 2: List Definitions (15 points)
        entity_list = read_file('entity_types.talon-list')
        rel_list = read_file('relationship_types.talon-list')
        
        list_score = 0
        if re.search(r'list:\s*user\.entity_type', entity_list):
            list_score += 3
        if all(k in entity_list for k in ['person', 'organization', 'location']):
            list_score += 4
            
        if re.search(r'list:\s*user\.relationship_type', rel_list):
            list_score += 4
        if all(k in rel_list for k in ['member_of', 'leader_of', 'located_at']):
            list_score += 4
            
        score += list_score
        feedback_parts.append(f"List definitions score: {list_score}/15.")

        # Criterion 3 & 4: Python Setup & State Management (35 points)
        py_code = read_file('intel_mapper.py')
        py_score = 0
        state_score = 0
        
        if py_code:
            if 'Module' in py_code and 'actions' in py_code:
                py_score += 5
            if '.list(' in py_code and 'entity_type' in py_code and 'relationship_type' in py_code:
                py_score += 10
                
            # Try AST parsing for rigorous checks, fallback to text matching if syntax error
            try:
                tree = ast.parse(py_code)
                funcs = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
                if 'set_entity_subject' in funcs and 'set_entity_target' in funcs:
                    state_score += 10
                if 'link_entities' in funcs and 'clear_graph' in funcs:
                    state_score += 5
            except SyntaxError:
                feedback_parts.append("SyntaxError in intel_mapper.py, falling back to string matching.")
                if 'def set_entity_subject' in py_code and 'def set_entity_target' in py_code:
                    state_score += 8
                if 'def link_entities' in py_code and 'def clear_graph' in py_code:
                    state_score += 4
                    
            if 'actions.edit.selected_text' in py_code:
                state_score += 5
                
        score += py_score + state_score
        feedback_parts.append(f"Python module score: {py_score}/15, State management score: {state_score}/20.")

        # Criterion 5: Voice Command Mapping (15 points)
        talon_code = read_file('intel_mapper.talon')
        cmd_score = 0
        if talon_code:
            if re.search(r'entity subject.*user\.entity_type', talon_code) and 'user.set_entity_subject' in talon_code:
                cmd_score += 5
            if re.search(r'entity link.*user\.relationship_type', talon_code) and 'user.link_entities' in talon_code:
                cmd_score += 5
            if 'entity export' in talon_code and 'user.export_graph' in talon_code:
                cmd_score += 5
                
        score += cmd_score
        feedback_parts.append(f"Voice commands score: {cmd_score}/15.")

        # Criterion 6: Export Accuracy Configuration (25 points)
        csv_score = 0
        if py_code:
            if 'csv' in py_code:
                csv_score += 5
            if 'nodes.csv' in py_code and 'edges.csv' in py_code:
                csv_score += 10
            # Check for header references
            if 'id' in py_code and 'type' in py_code and 'source' in py_code and 'target' in py_code:
                csv_score += 10
                
        score += csv_score
        feedback_parts.append(f"CSV export configuration score: {csv_score}/25.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification encountered an error: {str(e)}"}
        
    finally:
        # Cleanup
        for root, dirs, files in os.walk(temp_dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(temp_dir)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }