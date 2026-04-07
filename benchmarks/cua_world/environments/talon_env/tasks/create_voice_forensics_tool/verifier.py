#!/usr/bin/env python3
"""
Verifier for create_voice_forensics_tool task.

Verification Strategy:
1. Verify files exist in the correct Windows APPDATA directory.
2. Verify Python syntax is valid using AST.
3. Inspect Python AST strings for expected execution logic (hashlib, CSV, clipboard, append file).
4. Verify Talon commands mapping logic.
5. Check if the log file was actually generated (Proves execution and testing).
"""

import json
import tempfile
import os
import ast
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_voice_forensics_tool(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows C:/ path translation for Docker
        copy_from_env("C:/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')
    
    score = 0
    feedback_parts = []

    # Criterion 1: File Structure
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("✅ Both required .py and .talon files created")
    else:
        if not py_exists:
            feedback_parts.append("❌ forensics.py missing")
        if not talon_exists:
            feedback_parts.append("❌ forensics.talon missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Syntax Validation
    syntax_valid = False
    try:
        parsed_ast = ast.parse(py_content)
        syntax_valid = True
        score += 15
        feedback_parts.append("✅ Python syntax valid")
    except SyntaxError as e:
        feedback_parts.append(f"❌ Python syntax error in generated code: {e}")

    # Criterion 3: Core Business Logic (AST / Text Parsing)
    has_hash_logic = False
    has_csv_logic = False
    has_clipboard_logic = False
    
    if syntax_valid:
        code_str = py_content.lower()
        
        # Hashing logic presence
        if 'hashlib' in code_str and 'sha256' in code_str:
            has_hash_logic = True
            score += 15
            feedback_parts.append("✅ SHA-256 logic found")
        else:
            feedback_parts.append("❌ Missing hashlib/SHA-256 logic")
            
        # CSV mapping logic presence
        if 'malware_bazaar.csv' in code_str:
            if 'csv' in code_str or 'split' in code_str or 'pandas' in code_str:
                has_csv_logic = True
                score += 15
                feedback_parts.append("✅ CSV parsing logic found")
            else:
                feedback_parts.append("❌ Database path found but parsing logic missing")
        else:
            feedback_parts.append("❌ Target database path missing in script")
            
        # Talon Clipboard API logic presence
        if 'clip.text()' in code_str or 'actions.edit.copy(' in code_str:
            has_clipboard_logic = True
            score += 15
            feedback_parts.append("✅ Clipboard integration found")
        else:
            feedback_parts.append("❌ Missing clipboard integration (clip.text / edit.copy)")

    # Criterion 4: Talon file mappings
    t_content_low = talon_content.lower()
    if 'triage file' in t_content_low and 'evidence note' in t_content_low:
        score += 10
        feedback_parts.append("✅ Voice commands mapped correctly in .talon file")
    else:
        feedback_parts.append("❌ Missing required voice command triggers in .talon")

    # Criterion 5: Log Execution (Anti-gaming check)
    log_exists = result.get('log_exists', False)
    log_content = result.get('log_content', '')
    
    if log_exists and ('signature' in log_content.lower() or 'note:' in log_content.lower()):
        score += 20
        feedback_parts.append("✅ Output log generated successfully (Proves real execution)")
    else:
        if py_exists and 'evidence_log.txt' in code_str:
            score += 10
            feedback_parts.append("⚠️ Logging logic written but output log wasn't triggered/executed")
        else:
            feedback_parts.append("❌ Missing file logging functionality")

    # Optional VLM Validation for Trajectory Assurance
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_prompt = "Did the user edit Python code or Talon configuration files in a text editor like VSCode or Notepad? Answer true or false in JSON format: {\"edited_code\": true/false}"
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('edited_code'):
                feedback_parts.append("✅ VLM confirmed visual code editing trajectory")
            else:
                feedback_parts.append("⚠️ VLM did not clearly observe code editing")

    # Success conditions
    key_logic = has_hash_logic and has_csv_logic and py_exists and talon_exists
    passed = score >= 75 and key_logic
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }