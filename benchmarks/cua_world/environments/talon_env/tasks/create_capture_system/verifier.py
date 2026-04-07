#!/usr/bin/env python3
"""
Verifier for Talon create_capture_system task.

Uses MULTIPLE INDEPENDENT SIGNALS:
1. File existence and directory structure verification
2. Timestamps check (anti-gaming: files must be modified after task start)
3. Syntactic and structural content checks on declarative (.talon-list, .talon) and Python (.py) files
4. Cross-reference integrity between the files
5. VLM Trajectory analysis to ensure manual editing took place
"""

import json
import os
import tempfile
import re
import ast
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_capture_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_hex = metadata.get('required_hex_codes', [])

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
    
    # Check directory
    if result.get("dir_exists", False):
        score += 5
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("css_colors directory missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    files = result.get("files", {})
    
    # -------------------------------------------------------------
    # 1. Verify List File (css_colors.talon-list) - 30 points total
    # -------------------------------------------------------------
    list_file = files.get("css_colors.talon-list", {})
    if list_file.get("exists", False):
        score += 5
        content = list_file.get("content", "")
        
        # Anti-gaming: Timestamp check
        if list_file.get("created_during_task", False):
            # Header check
            if re.search(r'list:\s*user\.css_color', content) and "-" in content:
                score += 5
                
            # Content check: Extract hex lines
            hex_lines = re.findall(r'^[\w\s]+:\s*(#[0-9A-Fa-f]{6})\s*$', content, re.MULTILINE)
            if len(hex_lines) >= 12:
                score += 10
                feedback_parts.append(f"List has {len(hex_lines)} entries")
            elif len(hex_lines) > 0:
                score += 5
                feedback_parts.append(f"List has only {len(hex_lines)} entries (needed 12)")
                
            # Content check: Verify standard hex codes
            found_req_hex = [h.upper() for h in hex_lines if h.upper() in required_hex]
            if len(found_req_hex) >= 5:
                score += 10
            elif len(found_req_hex) > 0:
                score += 5
        else:
            feedback_parts.append("List file existed before task (gaming detected)")
    else:
        feedback_parts.append("List file missing")

    # -------------------------------------------------------------
    # 2. Verify Python File (css_colors.py) - 35 points total
    # -------------------------------------------------------------
    py_file = files.get("css_colors.py", {})
    py_valid = False
    if py_file.get("exists", False):
        score += 5
        content = py_file.get("content", "")
        
        if py_file.get("created_during_task", False):
            # Import check
            if "Module" in content and "Context" in content and "talon" in content:
                score += 5
                
            # List declaration check
            if re.search(r'\.list\(\s*["\']css_color["\']', content):
                score += 8
                
            # Capture definition check
            if re.search(r'@mod\.capture\(\s*rule\s*=\s*["\']\{user\.css_color\}["\']\s*\)', content) or \
               re.search(r'@[\w\.]+\.capture\(.*?\{user\.css_color\}.*?\)', content):
                score += 10
                
            # Syntax validation
            try:
                ast.parse(content)
                score += 7
                py_valid = True
            except SyntaxError:
                feedback_parts.append("Python file has syntax errors")
        else:
            feedback_parts.append("Python file existed before task (gaming detected)")
    else:
        feedback_parts.append("Python file missing")

    # -------------------------------------------------------------
    # 3. Verify Talon Command File (css_colors.talon) - 25 points total
    # -------------------------------------------------------------
    talon_file = files.get("css_colors.talon", {})
    if talon_file.get("exists", False):
        score += 5
        content = talon_file.get("content", "")
        
        if talon_file.get("created_during_task", False):
            # Cross-reference check (uses the capture)
            if "<user.css_color>" in content:
                score += 8
                
            # Action checks
            if "insert(" in content:
                score += 7
            if "clip" in content:
                score += 5
        else:
            feedback_parts.append("Talon file existed before task (gaming detected)")
    else:
        feedback_parts.append("Talon file missing")

    # -------------------------------------------------------------
    # 4. Cross-Reference Integrity (5 points)
    # -------------------------------------------------------------
    if "list: user.css_color" in list_file.get("content", "") and py_valid and "<user.css_color>" in talon_file.get("content", ""):
        score += 5
        feedback_parts.append("Cross-references intact")

    # -------------------------------------------------------------
    # 5. VLM Trajectory Verification
    # -------------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Review these screenshots from an agent's desktop trajectory.
        Did the agent use a text editor (like Notepad) to manually type or edit code files?
        Look for evidence of files being created and text (Python/Talon code) being typed.
        Respond with {"evidence_of_editing": true/false}.
        """
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if not parsed.get("evidence_of_editing", False):
                score = min(score, 40) # Cap score if no visual evidence of work
                feedback_parts.append("VLM found no evidence of manual text editing")

    # -------------------------------------------------------------
    # Final Scoring
    # -------------------------------------------------------------
    passed = score >= 70 and list_file.get("exists") and py_file.get("exists") and talon_file.get("exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "Verification complete"
    }