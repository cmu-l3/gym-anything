#!/usr/bin/env python3
"""
Verifier for create_legal_citation_formatter task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File Structure (10 pts)
2. Talon Reporter List (15 pts) - Exact mappings verification
3. Python Setup (15 pts) - AST check for Module & actions
4. Case Formatting Logic (15 pts) - Validates title casing and insertions
5. Statute Formatting Logic (15 pts) - Validates statutory formats & symbols
6. Talon Command Syntax (15 pts) - Signature matching
7. VLM Trajectory (15 pts) - Verifies manual agent typing over time
"""

import json
import tempfile
import os
import re
import ast
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_whitespace(text: str) -> str:
    """Normalizes whitespace to allow for minor syntax formatting variations."""
    return re.sub(r'\s+', ' ', text).strip()

def verify_legal_citations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_json_path = metadata.get('result_json_path', "C:\\temp\\task_result.json")

    # Extract JSON payload securely using copy_from_env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Early Check: Anti-Gaming
    if not result.get('target_dir_exists', False):
        return {"passed": False, "score": 0, "feedback": "The target directory 'legal_citations' was never created."}

    files = result.get('files', {})

    # ================================================================
    # CRITERION 1: File Structure (10 points)
    # ================================================================
    has_list = 'reporters.talon-list' in files
    has_py = 'legal_citations.py' in files
    has_talon = 'legal_citations.talon' in files

    if has_list and has_py and has_talon:
        score += 10
        feedback.append("✅ All 3 required files present.")
    else:
        feedback.append(f"❌ Missing files (list:{has_list}, py:{has_py}, talon:{has_talon})")
        if not files:
            return {"passed": False, "score": 0, "feedback": "No files created."}

    # ================================================================
    # CRITERION 2: Reporter List (15 points)
    # ================================================================
    if has_list:
        content = files['reporters.talon-list'].lower()
        if 'list: user.legal_reporter' in content:
            score += 5
            
        required_reporters = [
            "united states:", "supreme court:", "lawyers edition:",
            "federal third:", "federal second:", "federal supplement:",
            "federal supplement second:", "regional atlantic:",
            "regional north eastern:", "regional pacific:"
        ]
        found_reps = sum(1 for r in required_reporters if r in content)
        if found_reps == 10:
            score += 10
            feedback.append("✅ All 10 legal reporters mapped correctly.")
        else:
            score += found_reps
            feedback.append(f"⚠️ Found {found_reps}/10 legal reporters.")

    # ================================================================
    # CRITERION 3: Python Setup (15 points)
    # ================================================================
    py_content = files.get('legal_citations.py', '')
    if has_py:
        try:
            tree = ast.parse(py_content)
            has_module = False
            has_action_class = False
            for node in ast.walk(tree):
                if isinstance(node, ast.Call) and getattr(node.func, 'id', '') == 'Module':
                    has_module = True
                if isinstance(node, ast.ClassDef):
                    for dec in node.decorator_list:
                        if isinstance(dec, ast.Attribute) and dec.attr == 'action_class':
                            has_action_class = True
                            
            if has_module and has_action_class:
                score += 15
                feedback.append("✅ Python Module and @mod.action_class detected.")
            else:
                feedback.append("❌ Python Module architecture incomplete.")
        except SyntaxError:
            feedback.append("❌ Python file contains syntax errors.")

    # ================================================================
    # CRITERIA 4 & 5: Python Formatting Logic (30 points)
    # ================================================================
    if has_py:
        has_title = '.title(' in py_content or 'title()' in py_content
        has_insert = 'actions.insert(' in py_content
        has_section = '§' in py_content

        # Case Logic
        if 'format_insert_case' in py_content:
            if has_title and has_insert:
                score += 15
                feedback.append("✅ Case logic invokes Title Case and insert().")
            else:
                score += 5
                feedback.append("⚠️ Case logic defined but missing necessary string methods.")

        # Statute Logic
        if 'format_insert_statute' in py_content:
            if has_section and has_insert and 'U.S.C.' in py_content:
                score += 15
                feedback.append("✅ Statute logic handles the § symbol and formatting.")
            else:
                score += 5
                feedback.append("⚠️ Statute logic defined but missing § symbol or insert().")

    # ================================================================
    # CRITERION 6: Talon Command Syntax (15 points)
    # ================================================================
    if has_talon:
        talon_content = files['legal_citations.talon'].lower()
        norm_content = normalize_whitespace(talon_content)
        
        case_cmd = normalize_whitespace('cite case <user.text> volume <number> reporter {user.legal_reporter} page <number> year <number>')
        stat_cmd = normalize_whitespace('cite statute title <number> section <user.text> year <number>')

        if case_cmd in norm_content:
            score += 7.5
            feedback.append("✅ Case voice command signature verified.")
        if stat_cmd in norm_content:
            score += 7.5
            feedback.append("✅ Statute voice command signature verified.")

    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (15 points)
    # ================================================================
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames and final:
                vlm_prompt = """Did the agent actively type code into a text editor across these frames to create legal citation configuration files?
                Look for:
                1. A text editor (like Notepad) open on screen.
                2. Progressive typing of Talon or Python code related to legal citations across the frames.
                Respond strictly in JSON format: {"actively_typed": true/false}"""
                
                vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
                
                if vlm_result.get('parsed', {}).get('actively_typed', False):
                    score += 15
                    feedback.append("✅ VLM confirmed progressive active typing.")
                else:
                    feedback.append("❌ VLM did not detect active typing sequence.")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback.append(f"⚠️ VLM Error: {e}")

    passed = score >= 80
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }