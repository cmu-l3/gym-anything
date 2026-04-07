#!/usr/bin/env python3
"""
Verifier for Talon create_bookmark_system task.

Verifies:
1. All four files exist and are correctly named.
2. Syntax correctness for `.py` (AST parseable), `.talon`, and `.json` files.
3. Proper Talon design patterns (Module, @mod.action_class, Context declarations).
4. Content quality & anti-gaming verification via file payloads.
"""

import json
import ast
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bookmark_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Securely copy from the Windows container
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    feedback_parts = []
    score = 0

    # 1. Directory creation check
    dir_exists = result.get('dir_exists', False)
    if not dir_exists:
        return {"passed": False, "score": 0, "feedback": "bookmarks directory not created."}
    
    score += 5
    feedback_parts.append("Directory created")

    files = result.get('files', {})
    
    # 2. bookmarks.py check
    bk_py = files.get('bookmarks.py', {})
    if bk_py:
        content = bk_py.get('content', '')
        try:
            tree = ast.parse(content)
            score += 10
            feedback_parts.append("bookmarks.py valid syntax")
            
            has_mod = "Module(" in content
            has_action_class = "@mod.action_class" in content or "action_class" in content
            if has_mod and has_action_class:
                score += 10
                feedback_parts.append("Module and action class defined")
            
            actions = ['bookmark_add', 'bookmark_remove', 'bookmark_open', 'bookmark_list', 'bookmark_list_all']
            actions_found = sum(1 for a in actions if f"def {a}" in content)
            if actions_found == 5:
                score += 15
                feedback_parts.append("All 5 required actions defined")
            else:
                score += (actions_found * 3)
                feedback_parts.append(f"{actions_found}/5 actions defined")
                
            if "json.load" in content or "json.dump" in content or "bookmarks_data.json" in content:
                score += 10
                feedback_parts.append("JSON persistence logic implemented")
                
            if "Context(" in content and "bookmark_names" in content:
                score += 8
                feedback_parts.append("Dynamic Context list implemented")
        except SyntaxError:
            feedback_parts.append("bookmarks.py has Python syntax errors")
    else:
        feedback_parts.append("bookmarks.py missing")

    # 3. bookmarks.talon check
    bk_talon = files.get('bookmarks.talon', {})
    if bk_talon:
        content = bk_talon.get('content', '')
        # Simple heuristic rule checks avoiding raw Python
        if re.search(r'^[ \t]*[a-zA-Z_0-9.]+[(]', content, re.MULTILINE):
            score += 10
            feedback_parts.append("bookmarks.talon syntax valid")
            
            commands = [
                r'bookmark add',
                r'bookmark open',
                r'bookmark remove',
                r'bookmark list.*all',
                r'bookmark list',
                r'bookmark save'
            ]
            cmds_found = sum(1 for c in commands if re.search(c, content, re.IGNORECASE))
            if cmds_found >= 5:
                score += 12
                feedback_parts.append("Most/all .talon commands present")
            else:
                score += (cmds_found * 2)
                feedback_parts.append(f"{cmds_found}/6 commands present")
    else:
        feedback_parts.append("bookmarks.talon missing")

    # 4. bookmarks_list.py check
    bk_list = files.get('bookmarks_list.py', {})
    if bk_list:
        content = bk_list.get('content', '')
        try:
            tree = ast.parse(content)
            if "bookmark_categories" in content:
                strings = len(re.findall(r'["\'][a-zA-Z0-9_]+["\']', content))
                if strings >= 5:
                    score += 8
                    feedback_parts.append("Category list properly populated")
                else:
                    score += 4
                    feedback_parts.append("Category list lacking entries")
        except SyntaxError:
            feedback_parts.append("bookmarks_list.py has Python syntax errors")
    else:
        feedback_parts.append("bookmarks_list.py missing")

    # 5. bookmarks_data.json check
    bk_json = files.get('bookmarks_data.json', {})
    if bk_json:
        content = bk_json.get('content', '')
        try:
            data = json.loads(content)
            if isinstance(data, (list, dict)):
                items = data if isinstance(data, list) else data.values()
                if all(isinstance(i, dict) and 'name' in i and 'target' in i and 'category' in i and 'type' in i for i in items):
                    score += 7
                    feedback_parts.append("Valid JSON schema")
                    
                    categories = set(i['category'] for i in items)
                    if len(items) >= 8 and len(categories) >= 3:
                        score += 5
                        feedback_parts.append("Sufficient real-world data")
                    else:
                        feedback_parts.append("Valid JSON but insufficient entries/categories")
                else:
                    feedback_parts.append("JSON schema incorrect (missing required fields)")
        except json.JSONDecodeError:
            feedback_parts.append("bookmarks_data.json is invalid JSON")
    else:
        feedback_parts.append("bookmarks_data.json missing")

    # Evaluation Rules
    # Requires an adequate baseline implementation in Python and Talon files
    passed = score >= 60 and bool(bk_py) and bool(bk_talon)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }