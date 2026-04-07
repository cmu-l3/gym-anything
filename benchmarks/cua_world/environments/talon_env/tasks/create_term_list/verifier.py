#!/usr/bin/env python3
"""
Verifier for create_term_list task.

VERIFICATION METRICS:
1. Programmatic: File existence and modification timestamps (anti-gaming check).
2. Programmatic: Syntax and content check of `medical_terms.talon-list`.
3. Programmatic: Syntax and rule parsing of `medical_dictation.talon`.
4. VLM Trajectory: Confirms the user edited the files in a text editor like Notepad.
"""

import os
import json
import tempfile
import re
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_TERMS = {
    "blood pressure": "BP",
    "heart rate": "HR",
    "complete blood count": "CBC",
    "white blood cell": "WBC",
    "red blood cell": "RBC",
    "electrocardiogram": "ECG",
    "magnetic resonance imaging": "MRI",
    "computed tomography": "CT",
    "intensive care unit": "ICU",
    "emergency department": "ED",
    "chief complaint": "CC",
    "history of present illness": "HPI",
    "review of systems": "ROS",
    "past medical history": "PMH",
    "nothing by mouth": "NPO"
}

VLM_PROMPT = """You are evaluating an AI agent's performance on a computer desktop task.
The agent was supposed to create two Talon voice command files using a text editor (like Notepad).

Look at these screenshots from the agent's trajectory:
1. Did the agent open a text editor (e.g., Notepad or VS Code)?
2. Is there evidence of the agent actively typing or pasting medical terms (like "blood pressure", "heart rate") and Talon commands (like "med <user.medical_terms>") into the editor?

Respond strictly in JSON format:
{
    "opened_editor": true/false,
    "typed_content": true/false,
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_create_term_list(traj, env_info, task_info):
    """Verifies the proper creation of Talon list and command files."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON Metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    list_exists = result_data.get('list_exists', False)
    cmd_exists = result_data.get('cmd_exists', False)
    task_start = result_data.get('task_start', 0)
    list_mtime = result_data.get('list_mtime', 0)
    
    # Anti-gaming: Ensure files were created during the task
    created_during_task = True
    if list_exists and list_mtime > 0 and task_start > 0:
        if list_mtime < task_start - 10:  # 10s allowable jitter
            created_during_task = False
            
    if not created_during_task:
        return {"passed": False, "score": 0, "feedback": "Files pre-date task start (anti-gaming check failed)."}

    # 2. Verify List File Content
    list_content = ""
    if list_exists:
        score += 10
        feedback_parts.append("✅ List file exists")
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("C:\\workspace\\medical_terms.talon-list", temp_list.name)
            with open(temp_list.name, 'r', encoding='utf-8', errors='ignore') as f:
                list_content = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(temp_list.name):
                os.unlink(temp_list.name)
        
        # Analyze syntax
        lines = [line.strip() for line in list_content.split('\n')]
        lines = [line for line in lines if line and not line.startswith('#')]
        
        if lines:
            if lines[0] == 'list: user.medical_terms':
                score += 10
                feedback_parts.append("✅ List header correct")
            else:
                feedback_parts.append("❌ List header incorrect")
            
            if '-' in lines:
                score += 5
                
            found_terms = 0
            for term, abbr in EXPECTED_TERMS.items():
                expected_line = f"{term}:{abbr}".lower().replace(" ", "")
                for line in lines:
                    if expected_line == line.lower().replace(" ", ""):
                        found_terms += 1
                        break
            
            term_score = int((found_terms / 15.0) * 15)
            score += term_score
            feedback_parts.append(f"✅ Found {found_terms}/15 terms")
    else:
        feedback_parts.append("❌ List file missing")

    # 3. Verify Command File Content
    cmd_content = ""
    if cmd_exists:
        score += 10
        feedback_parts.append("✅ Command file exists")
        temp_cmd = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("C:\\workspace\\medical_dictation.talon", temp_cmd.name)
            with open(temp_cmd.name, 'r', encoding='utf-8', errors='ignore') as f:
                cmd_content = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(temp_cmd.name):
                os.unlink(temp_cmd.name)
        
        # Verify required command syntax patterns
        has_med = bool(re.search(r'med\s*[<{]user\.medical_terms[>}]\s*:', cmd_content))
        has_expand = bool(re.search(r'med\s*expand\s*[<{]user\.medical_terms[>}]\s*:', cmd_content))
        has_insert = 'insert(' in cmd_content
        
        if has_med:
            score += 10
            feedback_parts.append("✅ 'med' command valid")
        if has_expand:
            score += 15
            feedback_parts.append("✅ 'med expand' command valid")
        if has_insert:
            score += 5
    else:
        feedback_parts.append("❌ Command file missing")

    # 4. Hybrid VLM Verification (Trajectory Evidence)
    query_vlm_func = env_info.get('query_vlm')
    if query_vlm_func:
        try:
            # Check trajectory progression instead of just final screenshot
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_result = query_vlm_func(prompt=VLM_PROMPT, images=frames)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("opened_editor"):
                        score += 10
                    if parsed.get("typed_content"):
                        score += 10
                        feedback_parts.append("✅ VLM confirmed trajectory editing")
                    else:
                        feedback_parts.append("❌ VLM found no typing evidence")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    # Need 70 points AND the foundational files to actually exist
    passed = score >= 70 and list_exists and cmd_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }