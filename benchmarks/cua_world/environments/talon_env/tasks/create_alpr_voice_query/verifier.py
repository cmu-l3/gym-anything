#!/usr/bin/env python3
"""
Verifier for ALPR Voice Query task.
Uses AST checking on the host to avoid container dependencies.
"""

import json
import os
import tempfile
import logging
import ast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_alpr_voice_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. File Structure (10 pts)
    if result.get('dir_exists') and result.get('py_exists') and result.get('list_exists') and result.get('talon_exists'):
        score += 10
        feedback_parts.append("✅ All required files exist")
    else:
        feedback_parts.append("❌ Missing required files")
        
    # 2. Phonetic List Analysis (15 pts)
    list_content = result.get('list_content', '')
    mappings = {}
    list_dec_found = False
    
    for line in list_content.split('\n'):
        line = line.strip()
        if line.startswith('list:'):
            if 'user.police_phonetic' in line:
                list_dec_found = True
        elif ':' in line and not line.startswith('-'):
            parts = line.split(':')
            if len(parts) == 2:
                mappings[parts[0].strip().lower()] = parts[1].strip().upper()

    if list_dec_found:
        score += 5
        feedback_parts.append("✅ Correct Talon list declaration")
    
    expected_mappings = {
        'adam': 'A', 'boy': 'B', 'charles': 'C', 'david': 'D', 'edward': 'E',
        'frank': 'F', 'george': 'G', 'henry': 'H', 'ida': 'I', 'john': 'J',
        'king': 'K', 'lincoln': 'L', 'mary': 'M', 'nora': 'N', 'ocean': 'O',
        'paul': 'P', 'queen': 'Q', 'robert': 'R', 'sam': 'S', 'tom': 'T',
        'union': 'U', 'victor': 'V', 'william': 'W', 'xray': 'X', 'young': 'Y', 'zebra': 'Z',
        'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
        'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9'
    }
    
    correct_mappings = sum(1 for k, v in expected_mappings.items() if mappings.get(k) in [v, v.lower()])
    score += (correct_mappings / 36) * 10
    feedback_parts.append(f"List mappings: {correct_mappings}/36 correct")

    # 3. Talon Command Verification (10 pts)
    talon_content = result.get('talon_content', '').lower()
    if 'tow search <user.' in talon_content and 'lookup_towed_vehicle' in talon_content:
        score += 10
        feedback_parts.append("✅ Talon command successfully binds to custom action")
    else:
        feedback_parts.append("❌ Talon command bindings missing or incorrect")
        
    # 4 & 5. Python AST Analysis for Logic (50 pts)
    py_content = result.get('py_content', '')
    if py_content:
        try:
            tree = ast.parse(py_content)
            
            py_has_capture = False
            py_capture_join = False
            py_has_sqlite = False
            py_has_action_class = False
            py_action_db_connect = False
            py_action_inserts = False
            
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        if alias.name == 'sqlite3':
                            py_has_sqlite = True
                elif isinstance(node, ast.FunctionDef):
                    # Check decorators for mod.capture
                    for dec in node.decorator_list:
                        if isinstance(dec, ast.Call) and getattr(dec.func, 'attr', '') == 'capture':
                            py_has_capture = True
                        elif getattr(dec, 'attr', '') == 'capture':
                            py_has_capture = True
                            
                    if py_has_capture:
                        # Check if the list outputs are being joined inside the capture function
                        for subnode in ast.walk(node):
                            if isinstance(subnode, ast.Call) and getattr(subnode.func, 'attr', '') == 'join':
                                py_capture_join = True
                                
                elif isinstance(node, ast.ClassDef):
                    # Check for mod.action_class decorators
                    for dec in node.decorator_list:
                        if getattr(dec, 'attr', '') == 'action_class':
                            py_has_action_class = True
                            
                    # Check database connections and talon typing actions
                    for subnode in ast.walk(node):
                        if isinstance(subnode, ast.Call):
                            if getattr(subnode.func, 'attr', '') == 'connect':
                                py_action_db_connect = True
                            if getattr(subnode.func, 'attr', '') == 'insert':
                                py_action_inserts = True
                                
            # Scoring Capture Logic
            if py_has_capture:
                score += 10
                if py_capture_join:
                    score += 10
                    feedback_parts.append("✅ Python correctly defines and concatenates phonetic capture")
                    
            # Scoring SQL Logic
            if py_has_sqlite and py_has_action_class and py_action_db_connect:
                score += 20
                feedback_parts.append("✅ Python action successfully interfaces with SQLite database")
                
            # Scoring Formatting/Insertion
            if py_action_inserts:
                score += 10
                feedback_parts.append("✅ Python action properly writes back formats via actions.insert")
                
        except SyntaxError:
            feedback_parts.append("❌ Python file contains fatal syntax errors")
            
    # 6. VLM Trajectory Verification (15 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        query_vlm = env_info.get('query_vlm')
        
        if frames and query_vlm:
            vlm_prompt = """Look at these screenshots from an agent's trajectory. 
            Was the agent actively typing code (Python, .talon, or .talon-list files) in a text editor like Notepad?
            Respond in JSON format: {"edited_code": true} or {"edited_code": false}"""
            
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('edited_code', False):
                score += 15
                feedback_parts.append("✅ VLM verified active code editing workflow")
            else:
                feedback_parts.append("❌ VLM did not detect active code editing")
        else:
            feedback_parts.append("⚠️ VLM verification skipped (Missing frames or VLM)")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }