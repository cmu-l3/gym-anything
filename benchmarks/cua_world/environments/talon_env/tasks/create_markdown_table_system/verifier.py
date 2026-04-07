#!/usr/bin/env python3
"""
Verifier for create_markdown_table_system task.

Verifies multiple independent signals to prevent gaming:
1. File creation timestamps (anti-gaming check).
2. Proper structural logic of generated artifacts (`gdp_table.md`).
3. Correct definitions and Talon decorators in the Python API.
4. Correct Talon keybindings mapping `user.md_table_empty(number_1, number_2)` etc.
5. VLM trajectory verification to prove the agent did the work, didn't just dump pre-baked text.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_markdown_table_system(traj: list, env_info: dict, task_info: dict) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_md_exists', False)
    output_created_during = result.get('output_md_created_during_task', False)
    output_md_content = result.get('output_md_content', "")
    py_exists = result.get('py_exists', False)
    py_content = result.get('py_content', "")
    talon_exists = result.get('talon_exists', False)
    talon_content = result.get('talon_content', "")

    # ================================================================
    # CRITERION 1: Talon Python Module Implementation (25 Points)
    # ================================================================
    py_passed = False
    if py_exists:
        has_imports = 'from talon import' in py_content and 'Module' in py_content and 'actions' in py_content
        has_mod = re.search(r'mod\s*=\s*Module\(\)', py_content)
        has_decorator = '@mod.action_class' in py_content
        has_empty = 'def md_table_empty' in py_content
        has_from_csv = 'def md_table_from_csv' in py_content
        has_clipboard = 'def md_table_convert_clipboard' in py_content
        
        if has_imports and has_mod and has_decorator and has_empty and has_from_csv and has_clipboard:
            score += 25
            py_passed = True
            feedback_parts.append("Python module correctly implements Talon API.")
        else:
            score += 10
            feedback_parts.append("Python module exists but is missing required Talon decorators or action definitions.")
    else:
        feedback_parts.append("Python module is missing.")

    # ================================================================
    # CRITERION 2: Talon Command File Definition (20 Points)
    # ================================================================
    talon_passed = False
    if talon_exists:
        has_generate_cmd = re.search(r'table\s+generate\s+<number>\s+by\s+<number>', talon_content, re.IGNORECASE)
        has_generate_action = re.search(r'user\.md_table_empty\s*\(\s*number_1\s*,\s*number_2\s*\)', talon_content)
        has_paste_cmd = re.search(r'table\s+paste\s+csv', talon_content, re.IGNORECASE)
        has_paste_action = re.search(r'user\.md_table_convert_clipboard\s*\(\)', talon_content)
        
        if has_generate_cmd and has_paste_cmd and has_generate_action and has_paste_action:
            score += 20
            talon_passed = True
            feedback_parts.append("Talon .talon file correctly defines context-free keybindings.")
        else:
            score += 10
            feedback_parts.append("Talon .talon file exists but syntax or mapping is incomplete.")
    else:
        feedback_parts.append("Talon command file is missing.")

    # ================================================================
    # CRITERION 3: Markdown Artifact Output & Alignment (35 Points)
    # ================================================================
    artifact_passed = False
    if output_exists and output_created_during:
        lines = [ln.strip() for ln in output_md_content.strip().split('\n') if ln.strip()]
        
        if len(lines) >= 9: # Header, separator, 8 data lines
            # Check structure of Markdown Table
            is_valid_table = all(ln.startswith('|') and ln.endswith('|') for ln in lines)
            separator = lines[1]
            has_valid_separator = bool(re.match(r'^\|[\s\-:|]+\|$', separator))
            
            # Check alignment logic for the longest strings (e.g. "Population_Millions" -> 19 chars)
            # The country column should be padded to 14 chars ("United Kingdom")
            # If logic works, every cell in the first column should be padded to at least length 14
            col_0_widths = [len(ln.split('|')[1].strip()) for ln in lines if len(ln.split('|')) > 1]
            
            # The raw strings inside the markdown table pipes should be padded
            # Check if pipes are aligned by looking at string index positions of '|'
            pipe_counts = [ln.count('|') for ln in lines]
            consistent_pipes = all(p == 5 for p in pipe_counts) # 4 columns = 5 pipes
            
            if is_valid_table and has_valid_separator and consistent_pipes:
                score += 35
                artifact_passed = True
                feedback_parts.append("Markdown data generated with valid alignment formatting.")
            else:
                score += 15
                feedback_parts.append("Markdown artifact generated but alignment or pipe structure is malformed.")
        else:
            feedback_parts.append("Markdown artifact missing expected rows.")
    elif output_exists and not output_created_during:
        feedback_parts.append("Markdown artifact exists but was not created during the task.")
    else:
        feedback_parts.append("Markdown artifact was not generated.")

    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (20 Points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """You are verifying an agent completing a coding task.
        Look at these trajectory frames.
        1. Did the agent open a text editor (Notepad/VSCode/etc.) and write Python or Talon code?
        2. Did the agent use a console or terminal to run a script?
        3. Is there evidence of active work during the trajectory (not just a static screen)?
        
        Respond ONLY with a JSON object:
        {
            "wrote_code": true/false,
            "ran_script": true/false,
            "active_work": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            try:
                parsed = vlm_res.get('parsed', {})
                if parsed.get('wrote_code') and parsed.get('active_work'):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("VLM confirms active coding workflow.")
                else:
                    feedback_parts.append("VLM did not detect expected active coding workflow.")
            except Exception:
                feedback_parts.append("Failed to parse VLM response.")
    else:
        feedback_parts.append("VLM checking skipped (unavailable).")

    key_criteria_met = py_passed and talon_passed and artifact_passed
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }