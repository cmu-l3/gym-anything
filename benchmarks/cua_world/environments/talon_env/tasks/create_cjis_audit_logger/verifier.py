#!/usr/bin/env python3
"""
Verifier for CJIS Audit Logger Talon task.

Verification Strategy (Anti-Gaming enforced):
1. Code Extraction: Assesses code existence and paths.
2. AST Verification: Parses Python code to ensure `ui.register` is genuinely used 
   (prevents spoofing standard file-writers).
3. Dynamic Logging Verification: Checks the CSV for events that were generated 
   DURING the export phase (proving the hook is actively running).
4. VLM Trajectory: Confirms the agent actively developed the code in an editor.
"""

import json
import os
import ast
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cjis_audit_logger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use forward slashes for internal Docker paths mapped via copy_from_env
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Folder & File Creation (10 pts)
    # -------------------------------------------------------------------------
    py_exists = result.get("py_exists", False)
    talon_exists = result.get("talon_exists", False)
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("✅ Required .py and .talon files created")
    else:
        feedback_parts.append("❌ Missing required .py or .talon files")

    # -------------------------------------------------------------------------
    # 2. AST Verification for API Hook Registration (20 pts)
    # -------------------------------------------------------------------------
    py_content = result.get("py_content", "")
    hooks_registered = False
    
    if py_content:
        try:
            tree = ast.parse(py_content)
            register_calls = set()
            action_class_found = False
            
            for node in ast.walk(tree):
                # Look for ui.register('app_activate', ...)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                    if node.func.attr == 'register' and getattr(node.func.value, 'id', '') == 'ui':
                        if node.args and isinstance(node.args[0], ast.Constant):
                            register_calls.add(node.args[0].value)
                
                # Look for @mod.action_class defining the custom note action
                if isinstance(node, ast.FunctionDef) and 'audit_log_note' in node.name:
                    action_class_found = True

            if 'app_activate' in register_calls and 'app_deactivate' in register_calls:
                hooks_registered = True
                score += 20
                feedback_parts.append("✅ AST confirms valid ui.register hooks")
            else:
                feedback_parts.append("❌ AST missing expected ui.register callbacks")
                
        except SyntaxError:
            feedback_parts.append("❌ Syntax error in Python file")

    # -------------------------------------------------------------------------
    # 3. Dynamic App Tracking (40 pts)
    # -------------------------------------------------------------------------
    csv_exists = result.get("csv_exists", False)
    csv_content = result.get("csv_content", "").lower()
    
    if csv_exists:
        # We look for events dynamically generated during export_result.ps1
        has_notepad = "notepad" in csv_content and "activate" in csv_content
        has_paint = "mspaint" in csv_content and "activate" in csv_content
        
        if has_notepad and has_paint:
            score += 40
            feedback_parts.append("✅ CSV dynamically captured live app events")
        elif has_notepad or has_paint:
            score += 20
            feedback_parts.append("⚠️ CSV captured partial live events")
        else:
            feedback_parts.append("❌ CSV exists but failed to capture live events")
    else:
        feedback_parts.append("❌ CSV log file was never generated")

    # -------------------------------------------------------------------------
    # 4. Manual Note Command (20 pts)
    # -------------------------------------------------------------------------
    talon_content = result.get("talon_content", "").lower()
    if "audit note" in talon_content and "audit_log_note" in talon_content:
        score += 20
        feedback_parts.append("✅ Talon voice command correctly mapped")
    else:
        feedback_parts.append("❌ Talon command mapping missing or invalid")

    # -------------------------------------------------------------------------
    # 5. VLM Trajectory Verification (10 pts)
    # -------------------------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            prompt = """
            Look at these trajectory frames from a Windows desktop.
            Did the user actively type/edit Python code or configuration text relating to an 'audit logger', 'talon', or 'CSV' inside a text editor?
            Respond strictly in JSON format: {"wrote_code": true} or {"wrote_code": false}.
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("wrote_code"):
                score += 10
                feedback_parts.append("✅ VLM confirmed active code authoring")
            else:
                feedback_parts.append("❌ VLM did not observe active code authoring")

    # Validation criteria: Requires hooks to be present AND dynamic test to have passed
    key_criteria_met = hooks_registered and ("notepad" in csv_content and "activate" in csv_content)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }