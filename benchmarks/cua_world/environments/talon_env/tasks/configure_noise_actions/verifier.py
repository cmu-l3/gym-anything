#!/usr/bin/env python3
"""
Verifier for configure_noise_actions task in Talon Environment.
"""

import json
import os
import ast
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent that is configuring software (Talon Voice) using a Windows desktop.

Look at these screenshots showing the progression of the task.
Did the agent open a text editor (like Notepad, VSCode, etc.) and actively type/edit Python (`.py`) and/or Talon configuration (`.talon`) files related to "noise actions" (pop, hiss)?

Provide a JSON response:
{
    "used_editor": true/false,
    "edited_code_files": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_configure_noise_actions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # --- 1. Fetch Task Results JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    dir_exists = result.get('dir_exists', False)
    files_meta = result.get('files', {})

    if dir_exists:
        score += 5
        feedback_parts.append("✅ Directory created")
    else:
        feedback_parts.append("❌ Directory missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Anti-gaming: Check if files were created during the task
    created_during_task = any(f_meta.get('created_during_task', False) for f_meta in files_meta.values())
    if created_during_task:
        score += 10
        feedback_parts.append("✅ Files created during task session")
    else:
        feedback_parts.append("❌ Files pre-existed (Anti-gaming triggered)")

    # --- 2. Verify noise_actions.py ---
    py_meta = files_meta.get('noise_actions.py', {})
    if py_meta.get('exists') and py_meta.get('size', 0) > 50:
        temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
        try:
            copy_from_env("C:/tmp/noise_actions.py", temp_py.name)
            with open(temp_py.name, 'r') as f:
                py_code = f.read()
            
            # Syntax Check
            try:
                ast.parse(py_code)
                score += 10
                feedback_parts.append("✅ Python syntax valid")
            except SyntaxError:
                feedback_parts.append("❌ Python syntax error")

            # Content Check (30 points total via Regex/String matching)
            py_code_lower = py_code.lower()
            
            # Imports (5 pts)
            if all(imp in py_code for imp in ['Module', 'noise', 'ctrl', 'actions', 'ui']):
                score += 5
                feedback_parts.append("✅ Python imports correct")
            
            # Module & Setting (5 pts)
            if 'Module()' in py_code and 'setting(' in py_code and 'noise_scroll_speed' in py_code:
                score += 5
                feedback_parts.append("✅ Module setting defined")
            
            # Registration (5 pts)
            if 'noise.register' in py_code and 'pop' in py_code and 'hiss' in py_code:
                score += 5
                feedback_parts.append("✅ Noises registered")

            # Function Definitions (5 pts)
            if 'def on_pop' in py_code and 'def on_hiss' in py_code:
                score += 5
            
            # Context Logic (10 pts)
            if 'active_app' in py_code and ('[REVIEWED]' in py_code or '[reviewed]' in py_code):
                score += 5
            if 'mouse_scroll' in py_code and 'if active' in py_code_lower:
                score += 5
                
        except Exception as e:
            feedback_parts.append(f"❌ Failed to parse Python file: {e}")
        finally:
            if os.path.exists(temp_py.name):
                os.unlink(temp_py.name)
    else:
        feedback_parts.append("❌ noise_actions.py missing or empty")

    # --- 3. Verify noise_settings.talon ---
    talon_meta = files_meta.get('noise_settings.talon', {})
    if talon_meta.get('exists') and talon_meta.get('size', 0) > 10:
        temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
        try:
            copy_from_env("C:/tmp/noise_settings.talon", temp_talon.name)
            with open(temp_talon.name, 'r') as f:
                talon_code = f.read()
            
            if 'settings():' in talon_code and 'noise_scroll_speed' in talon_code and '3' in talon_code:
                score += 10
                feedback_parts.append("✅ Talon settings valid")
            else:
                feedback_parts.append("❌ Talon settings incomplete")
        finally:
            if os.path.exists(temp_talon.name):
                os.unlink(temp_talon.name)
    else:
        feedback_parts.append("❌ noise_settings.talon missing")

    # --- 4. Verify README.md ---
    readme_meta = files_meta.get('README.md', {})
    if readme_meta.get('exists') and readme_meta.get('size', 0) > 30:
        score += 5
        feedback_parts.append("✅ README created")

    # --- 5. VLM Trajectory Verification ---
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if images:
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("used_editor") and parsed.get("edited_code_files"):
                score += 30
                feedback_parts.append("✅ VLM verified active editing")
            else:
                feedback_parts.append("❌ VLM found no evidence of code editing")
        else:
            feedback_parts.append("⚠️ VLM evaluation failed")
    
    # Calculate final pass state
    passed = score >= 65 and created_during_task and (py_meta.get('exists', False))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }