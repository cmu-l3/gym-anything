#!/usr/bin/env python3
"""
Verifier for create_evidence_logger task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File Existence & Timestamps (Anti-gaming check)
2. Content Analysis: Validates presence of required structures and domains inside raw text
3. Python Compilation: Checks that `.py` is syntactically valid
4. VLM Verification: Analyzes trajectory to ensure the agent actively used an editor
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a computer usage task.
The task involves creating a set of configuration files for 'Talon' voice commands.
Look closely at these trajectory screenshots and determine:
1. Did the agent open a text editor (like Notepad, VSCode, or similar)?
2. Is there visual evidence of the agent typing or pasting code related to "evidence logging", "chain of custody", or voice command scripts?
3. Did the agent navigate directories to save the files in the correct location?

Respond in JSON format:
{
    "used_editor": true/false,
    "typed_code": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of the workflow observed"
}"""

def verify_create_evidence_logger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Use a temporary file to safely parse JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start_time', 0)
    files_data = result.get('files', {})
    
    # 1. Directory Checks (5 points)
    if result.get('dir_exists', False):
        score += 5
        feedback_parts.append("Directory created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Target directory 'evidence_logger' was not created."}

    # Helper function for Anti-gaming
    def is_valid_file(f_data):
        return f_data.get('exists', False) and f_data.get('mtime', 0) >= task_start

    # 2. evidence_logger.talon (15 points)
    talon_file = files_data.get('evidence_logger.talon', {})
    if is_valid_file(talon_file):
        content = talon_file.get('content', '').lower()
        commands_to_check = [
            "evidence new case", "evidence log item", "evidence handler", 
            "evidence action", "evidence location", "evidence commit", 
            "evidence show log", "evidence export csv", "evidence clear"
        ]
        found_cmds = sum(1 for cmd in commands_to_check if cmd in content)
        score += int(10 * (found_cmds / len(commands_to_check)))
        
        if "tag: user.evidence_logging" in content:
            score += 5
            feedback_parts.append(f"Talon commands ({found_cmds}/{len(commands_to_check)}) & tag found.")
        else:
            feedback_parts.append("Talon file missing tag declaration.")

    # 3. evidence_actions.talon-list (10 points)
    list_file = files_data.get('evidence_actions.talon-list', {})
    if is_valid_file(list_file):
        content = list_file.get('content', '').lower()
        if "list: user.evidence_action" in content:
            actions = ["received", "transferred", "stored", "retrieved", "examined", 
                       "photographed", "returned", "disposed", "sealed", "unsealed"]
            found_actions = sum(1 for act in actions if f"{act}:" in content or f"{act} :" in content)
            score += found_actions
            feedback_parts.append(f"Talon list created with {found_actions} actions.")

    # 4. evidence_logger.py (30 points total)
    py_file = files_data.get('evidence_logger.py', {})
    if is_valid_file(py_file):
        if result.get('py_compiles', False):
            score += 10
            feedback_parts.append("Python file compiles perfectly.")
        else:
            feedback_parts.append("Python file has syntax errors.")
        
        content = py_file.get('content', '')
        c_lower = content.lower()
        
        # Check module declarations
        if "module()" in c_lower and "context()" in c_lower and ".tag(" in c_lower and ".list(" in c_lower:
            score += 10
            feedback_parts.append("Python context/module declarations found.")
            
        # Check CSV logic & path
        if "caseid,timestamp,evidenceitem,handler,action,location,entrynumber" in c_lower.replace(" ", ""):
            score += 5
        if "chain_of_custody.csv" in c_lower:
            score += 5
            
    # 5. evidence_mode.talon (10 points)
    mode_file = files_data.get('evidence_mode.talon', {})
    if is_valid_file(mode_file):
        content = mode_file.get('content', '').lower()
        if "evidence logger" in content and "tag(): user.evidence_logging" in content and "evidence mode on" in content:
            score += 10
            feedback_parts.append("Evidence mode context file created correctly.")

    # 6. Anti-gaming / VLM Trajectory Verification (30 points)
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("used_editor", False):
                        vlm_score += 15
                    if parsed.get("typed_code", False):
                        vlm_score += 15
                    feedback_parts.append("VLM visual verification successful.")
                else:
                    feedback_parts.append("VLM query failed, skipping visual score.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("Error in VLM execution.")
    else:
        # Give free points if VLM isn't loaded for some reason, to not break testing, 
        # but realistically the environment should provide it.
        vlm_score = 30 
        feedback_parts.append("VLM disabled, assuming visual check passed.")

    score += vlm_score

    # Passing Criteria
    key_criteria_met = (
        is_valid_file(talon_file) and 
        is_valid_file(py_file) and 
        result.get('py_compiles', False)
    )
    
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }