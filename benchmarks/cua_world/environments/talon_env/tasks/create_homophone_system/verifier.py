#!/usr/bin/env python3
"""
Verifier for the Homophone System Task in Talon Voice.

Evaluates programmatic files created in a Windows environment:
1. Validates structure and specific legal pairs in homophones.csv
2. Parses AST to confirm Python action implementations
3. Validates Talon syntax and required voice commands
4. Verifies dictionary length and headers in Talon lists
"""

import json
import os
import tempfile
import ast
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_homophone_system(traj, env_info, task_info):
    """Verifies that all 4 homophone system files are properly constructed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = int(result.get("task_start", 0))
    files = result.get("files", {})

    # 0. Directory Check
    if result.get("directory_exists"):
        score += 3
        feedback_parts.append("Directory created (+3)")
    else:
        feedback_parts.append("Directory missing")
        return {"passed": False, "score": 0, "feedback": "Target directory not created"}

    # 1. Evaluate homophones.csv
    csv_file = files.get("homophones.csv", {})
    if csv_file.get("exists") and csv_file.get("mtime", 0) >= task_start:
        content = csv_file.get("content", "")
        lines = [line.strip() for line in content.split('\n') if line.strip()]
        
        groups = []
        for line in lines:
            parts = [p.strip().lower() for p in line.split(',')]
            groups.append(set(parts))
        
        if len(groups) > 0:
            score += 5
            feedback_parts.append("CSV valid (+5)")
        
        if len(groups) >= 20:
            score += 5
            feedback_parts.append(">= 20 homophone groups (+5)")
            
        required_pairs = [
            {"statute", "statue"}, {"counsel", "council"}, {"precedent", "president"},
            {"waiver", "waver"}, {"plaintiff", "plaintive"}, {"bail", "bale"},
            {"lien", "lean"}, {"tort", "torte"}, {"cite", "site", "sight"},
            {"indict", "indite"}, {"canon", "cannon"}, {"principal", "principle"},
            {"assent", "ascent"}, {"discrete", "discreet"}, {"elicit", "illicit"}
        ]
        
        pairs_found = 0
        for req in required_pairs:
            if any(req.issubset(g) for g in groups):
                pairs_found += 1
                
        score += pairs_found
        feedback_parts.append(f"{pairs_found}/15 required legal pairs found (+{pairs_found})")
    else:
        feedback_parts.append("homophones.csv missing/invalid")

    # 2. Evaluate homophone_manager.py
    py_file = files.get("homophone_manager.py", {})
    py_content = py_file.get("content", "")
    py_actions_found = set()
    
    if py_file.get("exists") and py_file.get("mtime", 0) >= task_start:
        try:
            tree = ast.parse(py_content)
            score += 5
            feedback_parts.append("Python syntax valid (+5)")
            
            # Module check
            has_module = "Module" in py_content and "talon" in py_content
            if has_module:
                score += 3
                feedback_parts.append("Talon Module logic (+3)")
                
            # Parse registered actions
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef):
                    py_actions_found.add(node.name)
                    
            if "homophones_get" in py_actions_found: score += 7; feedback_parts.append("Action homophones_get (+7)")
            if "homophones_cycle" in py_actions_found: score += 7; feedback_parts.append("Action homophones_cycle (+7)")
            if "homophones_add" in py_actions_found: score += 7; feedback_parts.append("Action homophones_add (+7)")
            if "homophones_show" in py_actions_found: score += 5; feedback_parts.append("Action homophones_show (+5)")
            
            # Check for CSV loading reference
            if "homophones.csv" in py_content:
                score += 5
                feedback_parts.append("CSV loading reference found (+5)")
                
        except SyntaxError:
            feedback_parts.append("Python syntax error")
    else:
        feedback_parts.append("homophone_manager.py missing/invalid")

    # 3. Evaluate homophone_commands.talon
    talon_file = files.get("homophone_commands.talon", {})
    talon_content = talon_file.get("content", "")
    
    if talon_file.get("exists") and talon_file.get("mtime", 0) >= task_start:
        lines = talon_content.split('\n')
        # Commands typically don't have leading indents
        cmds = [line.split(':')[0].strip() for line in lines if ':' in line and not line.startswith(' ') and not line.startswith('\t')]
        
        if any(re.match(r'^phones$', c) for c in cmds): score += 4; feedback_parts.append("Cmd 'phones' (+4)")
        if any(re.match(r'^phone that$', c) for c in cmds): score += 4; feedback_parts.append("Cmd 'phone that' (+4)")
        if any(re.match(r'^phone pick', c) for c in cmds): score += 3; feedback_parts.append("Cmd 'phone pick' (+3)")
        if any(re.match(r'^phone add', c) for c in cmds): score += 4; feedback_parts.append("Cmd 'phone add' (+4)")
        if any(re.match(r'^phone list$', c) for c in cmds): score += 3; feedback_parts.append("Cmd 'phone list' (+3)")
        
        # Cross file integration logic
        if "user.homophones_" in talon_content and len(py_actions_found) > 0:
            score += 5
            feedback_parts.append("Cross-file consistency logic (+5)")
    else:
        feedback_parts.append("homophone_commands.talon missing/invalid")

    # 4. Evaluate legal_terms.talon-list
    list_file = files.get("legal_terms.talon-list", {})
    list_content = list_file.get("content", "")
    
    if list_file.get("exists") and list_file.get("mtime", 0) >= task_start:
        lines = [l.strip() for l in list_content.split('\n') if l.strip()]
        
        # Check header
        if any("list: user.legal_terms" in l.lower() for l in lines[:5]):
            score += 3
            feedback_parts.append("List header correct (+3)")
            
        # Count list mappings
        entries = [l for l in lines if ':' in l and not l.startswith('list:') and not l.startswith('#')]
        if len(entries) >= 25:
            score += 7
            feedback_parts.append(">= 25 legal terms present (+7)")
        else:
            feedback_parts.append(f"Only {len(entries)} legal terms found")
    else:
        feedback_parts.append("legal_terms.talon-list missing/invalid")

    # Final scoring evaluation
    passed = score >= 60

    return {
        "passed": passed, 
        "score": min(score, 100), 
        "feedback": " | ".join(feedback_parts)
    }