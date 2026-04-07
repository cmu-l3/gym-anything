#!/usr/bin/env python3
"""
Verifier for create_cctv_surveillance_logger task.

Verification Strategy:
1. Validates files were created during the task (anti-gaming).
2. Uses regex/static analysis to ensure python syntax uses `actions.insert` and `datetime`.
3. Validates the talon-list format and mappings.
4. Validates the .talon voice commands match OS media controls and custom functions.
5. Uses VLM trajectory analysis to ensure the agent actively edited files.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Required target strings exactly as specified
REQUIRED_TARGETS = {
    "alpha": "Suspect 1 - John DOE (M/W, 6'1\", 190lbs, Neck tattoo)",
    "bravo": "Suspect 2 - Jane ROE (F/H, 5'4\", 130lbs, Blue backpack)",
    "vehicle1": "Suspect Vehicle - Gray Honda Civic CA Lic# 8XYZ123",
    "vehicle2": "Secondary Vehicle - Black Ford F-150 TX Lic# ABC1234"
}

def verify_cctv_logger(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results from Windows environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\cctv_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    start_time = result.get('task_start_time', 0)
    
    # ---------------------------------------------------------
    # Criterion 1: Files created and modified during task (15 pts)
    # ---------------------------------------------------------
    py_exists = result.get('py_exists', False)
    list_exists = result.get('list_exists', False)
    talon_exists = result.get('talon_exists', False)
    
    py_time = result.get('py_time', 0)
    list_time = result.get('list_time', 0)
    talon_time = result.get('talon_time', 0)
    
    files_created = sum([py_exists, list_exists, talon_exists])
    files_modified_during_task = sum([
        py_time >= start_time,
        list_time >= start_time,
        talon_time >= start_time
    ])
    
    if files_created == 3 and files_modified_during_task == 3:
        score += 15
        feedback_parts.append("✅ All 3 files created successfully")
    elif files_created > 0:
        score += (files_created * 5)
        feedback_parts.append(f"⚠️ Only {files_created}/3 files created")
    else:
        feedback_parts.append("❌ No files created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # Criterion 2: Python logic (.py) validation (25 pts)
    # ---------------------------------------------------------
    py_content = result.get('py_content', '')
    py_score = 0
    
    if "Module(" in py_content and "@mod.action_class" in py_content:
        py_score += 5
        
    if re.search(r'mod\.list\(\s*["\']cctv_target["\']', py_content):
        py_score += 5
        
    if "datetime" in py_content and "actions.insert" in py_content:
        py_score += 5
        
    # Check for formatting logic `[YYYY-MM-DD HH:MM:SS] - `
    if re.search(r'\[%Y-%m-%d %H:%M:%S\] -', py_content) or re.search(r'\[{.*?}\] -', py_content):
        py_score += 5
        
    # Check for hardcoded dict values
    targets_found = 0
    for key, val in REQUIRED_TARGETS.items():
        # Remove quotes to simplify fuzzy checking
        safe_val = val.replace('"', '').replace("'", "")
        safe_content = py_content.replace('"', '').replace("'", "")
        if safe_val in safe_content:
            targets_found += 1
            
    if targets_found == 4:
        py_score += 5
        
    score += py_score
    if py_score == 25:
        feedback_parts.append("✅ Python module logic is completely correct")
    else:
        feedback_parts.append(f"⚠️ Python logic partially correct ({py_score}/25)")

    # ---------------------------------------------------------
    # Criterion 3: Talon list (.talon-list) validation (15 pts)
    # ---------------------------------------------------------
    list_content = result.get('list_content', '')
    list_score = 0
    
    if re.search(r'list:\s*user\.cctv_target', list_content):
        list_score += 5
        
    if "target alpha: alpha" in list_content and "target bravo: bravo" in list_content:
        list_score += 5
    if "suspect vehicle: vehicle1" in list_content and "secondary vehicle: vehicle2" in list_content:
        list_score += 5
        
    score += list_score
    if list_score == 15:
        feedback_parts.append("✅ Talon list formatted correctly")
    else:
        feedback_parts.append(f"⚠️ Talon list format errors ({list_score}/15)")

    # ---------------------------------------------------------
    # Criterion 4: Talon Voice Commands (.talon) validation (20 pts)
    # ---------------------------------------------------------
    talon_content = result.get('talon_content', '')
    talon_score = 0
    
    # Check OS Media keys
    if re.search(r'vision play:\s*key\(play_pause\)', talon_content):
        talon_score += 3
    if re.search(r'vision pause:\s*key\(play_pause\)', talon_content):
        talon_score += 3
    if re.search(r'vision next:\s*key\(next\)', talon_content):
        talon_score += 3
    if re.search(r'vision back:\s*key\(prev\)', talon_content):
        talon_score += 3
        
    # Check custom actions
    if re.search(r'log event <user\.text>:\s*user\.cctv_log_event\(', talon_content):
        talon_score += 4
    if re.search(r'log target \{user\.cctv_target\}:\s*user\.cctv_insert_target\(', talon_content):
        talon_score += 4
        
    score += talon_score
    if talon_score == 20:
        feedback_parts.append("✅ Talon voice commands correctly bound")
    else:
        feedback_parts.append(f"⚠️ Talon bindings partially correct ({talon_score}/20)")

    # ---------------------------------------------------------
    # Criterion 5: VLM Trajectory Verification (25 pts)
    # Ensures the agent was actively typing code (Anti-gaming)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            feedback_parts.append("❌ No trajectory frames for VLM verification")
        else:
            prompt = """Analyze these screenshots from a Windows desktop session.
            Did the user/agent actively type or edit Python code and Talon configuration files in a text editor (like Notepad or VS Code)?
            Look for text editor windows containing code like `Module()`, `cctv_target`, `key(play_pause)`, etc.
            Respond in JSON format:
            {
                "is_editing_code": true/false,
                "confidence": "high/medium/low"
            }
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("is_editing_code", False):
                    vlm_score = 25
                    feedback_parts.append("✅ VLM confirmed active code editing")
                else:
                    feedback_parts.append("❌ VLM did not detect active code editing")
            else:
                feedback_parts.append("⚠️ VLM query failed, skipping visual verification")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("⚠️ VLM error occurred")
        
    score += vlm_score
    
    # Final Evaluation
    key_criteria_met = (files_created == 3 and py_score >= 15 and talon_score >= 10)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }