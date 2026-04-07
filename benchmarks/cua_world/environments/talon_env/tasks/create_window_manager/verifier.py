#!/usr/bin/env python3
"""
Verifier for create_window_manager task.

Evaluates the structural integrity, syntax correctness, and content validity 
of the agent-created Talon configuration files for window management.

Uses copy_from_env to read pre-exported JSON payload containing file contents.
"""

import sys
import os
import json
import logging
import tempfile
import ast
import re

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_window_manager(traj, env_info, task_info):
    """
    Verify the window management multi-file configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    dir_exists = result.get('dir_exists', False)
    files = result.get('files', {})

    # 1. Check Directory (5 pts)
    if dir_exists:
        score += 5
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("Target directory missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check File Existence & Anti-Gaming Timestamps (15 pts)
    files_present = 0
    all_new = True
    for fname, fdata in files.items():
        if fdata.get('exists'):
            files_present += 1
            if fdata.get('mtime', 0) <= task_start and task_start > 0:
                all_new = False

    score += (files_present * 2.5)
    if files_present > 0 and all_new:
        score += 5
        feedback_parts.append(f"{files_present}/4 files found and modified during task")
    else:
        feedback_parts.append("Timestamp mismatch (anti-gaming flag)")

    # 3. Verify window_snap.talon (20 pts)
    snap_talon = files.get('window_snap.talon', {}).get('content', '')
    if snap_talon:
        snap_score = 0
        required_snaps = ['super-left', 'super-right', 'super-up', 'super-down', 'super-home']
        multi_monitor = ['super-shift-left', 'super-shift-right']
        
        found_snaps = [s for s in required_snaps if s in snap_talon]
        found_multi = [s for s in multi_monitor if s in snap_talon]
        
        if len(found_snaps) >= 4: snap_score += 10
        elif len(found_snaps) > 0: snap_score += 5
        
        if len(found_multi) >= 1: snap_score += 5
        
        if re.search(r'^[a-zA-Z0-9\s]+:\s*(?:\n\s+)?key\(', snap_talon, re.MULTILINE):
            snap_score += 5
            
        score += snap_score
        feedback_parts.append(f"window_snap bindings: {len(found_snaps) + len(found_multi)} found")

    # 4. Verify virtual_desktops.talon (15 pts)
    desktop_talon = files.get('virtual_desktops.talon', {}).get('content', '')
    if desktop_talon:
        desk_score = 0
        required_desktops = ['super-ctrl-d', 'super-ctrl-f4', 'alt-tab', 'super-tab']
        
        found_desk = [s for s in required_desktops if s in desktop_talon]
        if 'super-ctrl-left' in desktop_talon or 'super-ctrl-right' in desktop_talon:
            found_desk.append('desktop-switch')
            
        if len(found_desk) >= 4: desk_score += 10
        elif len(found_desk) > 0: desk_score += 5
        
        if re.search(r'^[a-zA-Z0-9\s]+:\s*(?:\n\s+)?key\(', desktop_talon, re.MULTILINE):
            desk_score += 5
            
        score += desk_score
        feedback_parts.append(f"virtual_desktops bindings: {len(found_desk)} found")

    # 5. Verify window_actions.py (20 pts)
    py_code = files.get('window_actions.py', {}).get('content', '')
    py_compiles = False
    if py_code:
        try:
            tree = ast.parse(py_code)
            py_compiles = True
            score += 5
            
            has_mod_decl = False
            has_action_decorator = False
            has_snap = False
            has_focus = False
            
            for node in ast.walk(tree):
                if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
                    if getattr(node.value.func, 'id', '') == 'Module':
                        has_mod_decl = True
                elif isinstance(node, ast.ClassDef):
                    for dec in node.decorator_list:
                        if isinstance(dec, ast.Attribute) and dec.attr == 'action_class':
                            has_action_decorator = True
                    for item in node.body:
                        if isinstance(item, ast.FunctionDef):
                            if 'snap' in item.name.lower(): has_snap = True
                            if 'focus' in item.name.lower(): has_focus = True
                            
            if has_mod_decl: score += 5
            if has_action_decorator: score += 5
            if has_snap and has_focus: score += 5
            
            feedback_parts.append(f"Python module compiled (snap:{has_snap}, focus:{has_focus})")
        except SyntaxError:
            feedback_parts.append("Python file has syntax errors")

    # 6. Verify README.md (5 pts)
    readme = files.get('README.md', {}).get('content', '')
    if readme:
        headers = ['Snap', 'Desktop', 'Action']
        found_headers = [h for h in headers if h.lower() in readme.lower()]
        if len(found_headers) >= 2:
            score += 5
            feedback_parts.append("README documented")

    # 7. VLM Visual Work Verification (20 pts)
    if VLM_AVAILABLE and query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are verifying an agent that was tasked with creating text files using a code editor (e.g., Notepad, VS Code).
            Review these trajectory frames.
            1. Did the agent successfully open and use a text editor?
            2. Was the agent actively writing or editing configuration (.talon) or code (.py) files?
            
            Respond in JSON format:
            {
                "used_editor": true/false,
                "actively_writing": true/false
            }"""
            
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_editor"): score += 10
                if parsed.get("actively_writing"): score += 10
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM parsing failed")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM check error")
    else:
        # Give free points if VLM isn't available to prevent unfair failure
        score += 20
        feedback_parts.append("VLM skipped (auto-pass 20 pts)")

    key_criteria_met = dir_exists and py_compiles and files_present >= 3
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }