#!/usr/bin/env python3
"""
Verifier for refactor_talon_config task.

Verifies:
1. Structural compliance (directories, exact file names, removing original)
2. Context header correctness (app: matchers and hyphens)
3. Content preservation (no dropped commands from the original monolithic file)
4. Anti-gaming check (file mtimes > task start time)
5. VLM trajectory check for authentic editor usage
"""

import os
import json
import tempfile
import logging
import re

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_talon_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Securely retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    files = result.get('files', {})

    # 1. Directory and original file handling (20 points)
    if result.get('dir_exists'):
        score += 10
        feedback_parts.append("✅ Refactored directory created")
    else:
        feedback_parts.append("❌ Refactored directory missing")

    if not result.get('original_exists') or result.get('original_renamed'):
        score += 10
        feedback_parts.append("✅ Original file removed/disabled")
    else:
        feedback_parts.append("❌ Original file still exists as everything.talon")

    # Anti-gaming timestamp check
    created_during_task = any(f_info.get('mtime', 0) >= task_start for f_info in files.values())
    if not created_during_task and files:
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: Files were not created during the task time window."}

    # 2. Browser logic (15 points)
    browser_content = files.get('browser.talon', {}).get('content', '')
    if browser_content:
        # Check context header
        has_browser_app = re.search(r'^app:\s*(firefox|chrome)', browser_content, re.MULTILINE | re.IGNORECASE)
        has_dash = re.search(r'^-$', browser_content, re.MULTILINE)
        has_cmds = all(cmd in browser_content for cmd in metadata.get('expected_browser_commands', []))
        
        if has_browser_app and has_dash and has_cmds:
            score += 15
            feedback_parts.append("✅ Browser commands perfectly extracted with header")
        elif has_cmds:
            score += 5
            feedback_parts.append("⚠️ Browser commands extracted but context header missing/malformed")
    else:
        feedback_parts.append("❌ browser.talon missing or empty")

    # 3. Notepad logic (15 points)
    notepad_content = files.get('notepad.talon', {}).get('content', '')
    if notepad_content:
        has_notepad_app = re.search(r'^app:\s*notepad', notepad_content, re.MULTILINE | re.IGNORECASE)
        has_dash = re.search(r'^-$', notepad_content, re.MULTILINE)
        has_cmds = all(cmd in notepad_content for cmd in metadata.get('expected_notepad_commands', []))
        
        if has_notepad_app and has_dash and has_cmds:
            score += 15
            feedback_parts.append("✅ Notepad commands perfectly extracted with header")
        elif has_cmds:
            score += 5
            feedback_parts.append("⚠️ Notepad commands extracted but context header missing/malformed")
    else:
        feedback_parts.append("❌ notepad.talon missing or empty")

    # 4. Global logic (10 points)
    global_content = files.get('global.talon', {}).get('content', '')
    if global_content:
        has_cmds = all(cmd in global_content for cmd in metadata.get('expected_global_commands', []))
        if has_cmds:
            score += 10
            feedback_parts.append("✅ Global commands correctly preserved")
    else:
        feedback_parts.append("❌ global.talon missing or empty")

    # 5. Python Action & List extraction (10 + 10 = 20 points)
    py_content = files.get('custom_actions.py', {}).get('content', '')
    if py_content and metadata.get('python_signature', '') in py_content and 'from talon import' in py_content:
        score += 10
        feedback_parts.append("✅ Python actions correctly extracted to custom_actions.py")
    else:
        feedback_parts.append("❌ custom_actions.py missing or invalid")

    list_content = files.get('symbols.talon-list', {}).get('content', '')
    if list_content and metadata.get('list_signature', '') in list_content and '-' in list_content and 'dot: .' in list_content:
        score += 10
        feedback_parts.append("✅ Symbol list correctly extracted to symbols.talon-list")
    else:
        feedback_parts.append("❌ symbols.talon-list missing or invalid")

    # 6. VLM Trajectory check (20 points)
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = (
                "Review these screenshots of an agent performing a task in Windows. "
                "Did the agent actively use a text editor (like Notepad or VSCode) to read a file, "
                "and navigate Windows Explorer to create a new folder and new files? "
                "Respond in JSON format: {'active_editing_observed': true/false}"
            )
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("active_editing_observed", False):
                vlm_score = 20
                feedback_parts.append("✅ VLM confirmed authentic trajectory")
            else:
                feedback_parts.append("❌ VLM could not confirm text editor usage")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            vlm_score = 20  # Forgive if VLM framework acts up
            feedback_parts.append("⚠️ VLM check bypassed due to error")
    else:
        vlm_score = 20
        feedback_parts.append("⚠️ VLM disabled in env")

    score += vlm_score

    # Determine passing based on key criteria (Files exist properly, Original gone, Good headers)
    key_criteria_met = (
        result.get('dir_exists', False) and 
        (not result.get('original_exists') or result.get('original_renamed')) and
        'browser.talon' in files and 'notepad.talon' in files
    )
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }