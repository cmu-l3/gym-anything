#!/usr/bin/env python3
"""
Verifier for Create Shortcut Layer task in Talon.
Uses multi-criteria verification of configuration files and their contents,
along with trajectory-based VLM verification for anti-gaming.
"""

import os
import json
import re
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add imports for VLM utility
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Stubs if not running within the framework environment
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None

def verify_create_shortcut_layer(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Copy JSON result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path for copy_from_env
        copy_from_env("C:/temp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    target_dir_exists = result.get('target_dir_exists', False)
    files = result.get('files', {})

    # Criterion 1: Directory exists (5 points)
    if target_dir_exists:
        score += 5
        feedback_parts.append("Directory created")
    else:
        feedback_parts.append("Directory 'shortcut_layer' NOT created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: All 5 files exist and have timestamps > start (15 points total)
    expected_files = task_info.get('metadata', {}).get('required_files', [])
    files_exist = 0
    valid_timestamps = True
    
    for fname in expected_files:
        f_data = files.get(fname, {})
        if f_data.get('exists', False) and f_data.get('size_bytes', 0) > 0:
            files_exist += 1
            if f_data.get('mtime', 0) < task_start:
                valid_timestamps = False

    if files_exist == len(expected_files):
        score += 10
        feedback_parts.append("All required files exist")
    else:
        feedback_parts.append(f"{files_exist}/{len(expected_files)} files created")
        score += int(10 * (files_exist / len(expected_files)))

    if files_exist > 0 and valid_timestamps:
        score += 5
        feedback_parts.append("File timestamps valid")
    elif files_exist > 0:
        feedback_parts.append("File timestamps PRE-DATE task start (gaming detected)")
        valid_timestamps = False

    # Helper function to get content safely
    def get_content(filename):
        return files.get(filename, {}).get('content', '')

    # Criterion 3: Python module structure (12 points)
    py_content = get_content('shortcut_layer.py')
    py_structure_score = 0
    if 'Module()' in py_content or 'Module(' in py_content:
        py_structure_score += 4
    if 'setting' in py_content and 'shortcut_layer_enabled' in py_content:
        py_structure_score += 4
    if 'action_class' in py_content or 'actions.register' in py_content:
        py_structure_score += 4
    
    score += py_structure_score
    if py_structure_score == 12:
        feedback_parts.append("Python module structure correct")

    # Criterion 4: Python action definitions (12 points)
    actions = task_info.get('metadata', {}).get('required_actions', [])
    actions_found = sum(1 for a in actions if f"def {a}" in py_content or f" {a}(" in py_content)
    score += (actions_found * 2)  # 2 points per action, max 12
    if actions_found == len(actions):
        feedback_parts.append("All Python actions defined")

    # Criterion 5: Default .talon correct (10 points)
    default_content = get_content('shortcut_layer_default.talon').lower()
    default_score = 0
    if 'shortcut_layer_enabled' in default_content:
        default_score += 4
    if 'user.shortcut_save()' in default_content or 'shortcut_save()' in default_content:
        default_score += 2
    if 'user.shortcut_undo()' in default_content or 'shortcut_undo()' in default_content:
        default_score += 2
    if 'file save' in default_content and 'undo that' in default_content:
        default_score += 2
    
    score += default_score
    if default_score == 10:
        feedback_parts.append("Default .talon configured correctly")

    # Criterion 6: Vim .talon match and overrides (18 points)
    vim_content = get_content('shortcut_layer_vim.talon').lower()
    if ('vim' in vim_content or 'nvim' in vim_content) and ('win.title' in vim_content or 'app.name' in vim_content):
        score += 8
        feedback_parts.append("Vim context matcher correct")
        
    vim_overrides_score = 0
    if 'escape' in vim_content: vim_overrides_score += 2
    if ':w' in vim_content: vim_overrides_score += 2
    if ' u' in vim_content or 'key(u)' in vim_content or 'insert(u)' in vim_content: vim_overrides_score += 2
    if 'ctrl-r' in vim_content: vim_overrides_score += 2
    if ':bd' in vim_content: vim_overrides_score += 2
    score += vim_overrides_score

    # Criterion 7: VS Code .talon correct (8 points)
    vscode_content = get_content('shortcut_layer_vscode.talon').lower()
    if 'code' in vscode_content or 'visual studio' in vscode_content:
        score += 4
    if 'ctrl-shift-z' in vscode_content:
        score += 2
    if 'ctrl-g' in vscode_content:
        score += 2

    # Criterion 8: Browser .talon correct (8 points)
    browser_content = get_content('shortcut_layer_browser.talon').lower()
    if any(b in browser_content for b in ['chrome', 'firefox', 'edge', 'brave']):
        score += 4
    if 'ctrl-y' in browser_content:
        score += 2
    if 'ctrl-w' in browser_content:
        score += 2

    # Criterion 9: Cross-file consistency / Setting guard (7 points)
    settings_guards = sum(1 for c in [default_content, vim_content, vscode_content, browser_content] if 'shortcut_layer_enabled' in c)
    if settings_guards == 4:
        score += 7
        feedback_parts.append("Settings guard applied across all files")

    # =========================================================================
    # VLM Trajectory Verification (Anti-gaming check)
    # Ensure they actually opened a text editor and worked on the files
    # =========================================================================
    vlm_passed = True
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            prompt = (
                "Look at these screenshots showing a user's workflow. "
                "Did the user actively use a text editor (like Notepad, VS Code) "
                "to write configuration code/scripts? "
                "Respond in JSON format: {\"used_editor\": true/false}"
            )
            vlm_result = query_vlm(prompt=prompt, images=frames)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if not parsed.get("used_editor", False):
                    vlm_passed = False
                    feedback_parts.append("VLM Check Failed: No evidence of text editor usage in trajectory")
                    # Heavily penalize if it seems like a script just magically created the files
                    score = min(score, 30)
            else:
                logger.warning(f"VLM verification query failed: {vlm_result.get('error')}")

    # Determine final pass status
    # 60% threshold AND required files must exist AND timestamps valid AND VLM passed
    key_criteria_met = files_exist >= 3 and valid_timestamps and vlm_passed
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }