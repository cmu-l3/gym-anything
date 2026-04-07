#!/usr/bin/env python3
"""
Verifier for the repair_cif_parser_library task.

Evaluates if the agent correctly fixed the 5 CIF parsing bugs.
Uses multi-criteria scoring combining runtime test results, file modification timestamps,
and VLM-based trajectory verification to prevent gaming.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cif_parser(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cif_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get("task_start", 0)
    files = result.get("files", {})
    
    # Anti-gaming: Ensure files were actually modified during the task session
    files_modified = False
    for fname, fmeta in files.items():
        if fmeta and fmeta.get("mtime", 0) > task_start:
            files_modified = True
            
    if not files_modified:
        feedback_parts.append("No files were modified during the task session.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Evaluate Bug Fixes (20 pts each)
    if result.get("bug1_fixed"):
        score += 20
        feedback_parts.append("[+] Bug 1: Uncertainty stripping fixed")
    else:
        feedback_parts.append("[-] Bug 1: Uncertainty stripping failed")
        
    if result.get("bug2_fixed"):
        score += 20
        feedback_parts.append("[+] Bug 2: Quote stripping fixed")
    else:
        feedback_parts.append("[-] Bug 2: Quote stripping failed")
        
    if result.get("bug3_fixed"):
        score += 20
        feedback_parts.append("[+] Bug 3: Dynamic column mapping fixed")
    else:
        feedback_parts.append("[-] Bug 3: Dynamic column mapping failed")
        
    if result.get("bug4_fixed"):
        score += 20
        feedback_parts.append("[+] Bug 4: Multiline regex fixed")
    else:
        feedback_parts.append("[-] Bug 4: Multiline regex failed")
        
    if result.get("bug5_fixed"):
        score += 20
        feedback_parts.append("[+] Bug 5: Periodic boundaries fixed")
    else:
        feedback_parts.append("[-] Bug 5: Periodic boundaries failed")

    # Add any runtime errors encountered during hidden tests to feedback
    errors = result.get("errors", [])
    if errors:
        feedback_parts.append(f"Runtime Errors: {len(errors)} exceptions caught.")
        for err in errors[:2]:  # Show max 2 errors
            feedback_parts.append(f"  > {err}")

    # VLM Verification: Ensure VSCode was actually used for debugging
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """Look at these screenshots of a user's desktop over time. 
Did the user interact with Visual Studio Code to edit Python files (specifically parser.py or geometry.py) and run pytest or python commands in the terminal?
Respond strictly with a JSON object: {"used_vscode_and_ran_tests": true/false}"""
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res and vlm_res.get('parsed', {}).get('used_vscode_and_ran_tests'):
            vlm_passed = True
            feedback_parts.append("[+] VLM confirmed active VSCode usage")
        else:
            feedback_parts.append("[-] VLM could not confirm VSCode interaction")
    else:
        vlm_passed = True # Bypass if VLM not available

    # Final scoring determination
    key_criteria_met = files_modified and vlm_passed
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score if key_criteria_met else 0,
        "feedback": " | ".join(feedback_parts)
    }