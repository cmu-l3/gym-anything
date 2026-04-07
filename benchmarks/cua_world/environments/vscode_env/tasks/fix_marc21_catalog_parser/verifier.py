#!/usr/bin/env python3
"""
Verifier for the fix_marc21_catalog_parser task.
Checks if the 4 specific parsing bugs were fixed correctly.
Uses copy_from_env to safely retrieve execution results and JSON outputs.
"""

import os
import json
import tempfile
import logging
import re
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_marc_parser(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    parser_code = result.get("parser_code", "")
    parsed_json = result.get("parsed_json")
    
    score = 0
    feedback = []

    # 1. Anti-gaming check: Make sure parser.py was modified
    mtime = result.get("parser_mtime", 0)
    start_time = result.get("task_start_time", float('inf'))
    if mtime <= start_time:
        feedback.append("[-] parser.py was not modified during the task.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Read ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/app/ground_truth/expected_catalog.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        ground_truth = []
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 2. Check Bug 1: Directory Parsing (20 pts)
    # The bug was field_length = int(dir_data[i+3:i+6]) and start_char = int(dir_data[i+6:i+11])
    # The fix is i+3:i+7 and i+7:i+12
    dir_fix_regex = re.search(r'i\+3\s*:\s*i\+7', parser_code)
    offset_fix_regex = re.search(r'i\+7\s*:\s*i\+12', parser_code)
    
    valid_data_extracted = False
    if parsed_json and isinstance(parsed_json, list) and len(parsed_json) > 0:
        if "245" in parsed_json[0] and "001" in parsed_json[0]:
            valid_data_extracted = True

    if (dir_fix_regex and offset_fix_regex) or valid_data_extracted:
        score += 20
        feedback.append("[+] Bug 1 (Directory Offset Slice) fixed (20/20)")
    else:
        feedback.append("[-] Bug 1 not fixed: directory lengths/offsets still incorrect (0/20)")

    # 3. Check Bug 2: Encoding (20 pts)
    # Check if they look at leader[9] or use utf-8 properly
    encoding_fix_regex = re.search(r'leader\[9\]|utf-8|utf8', parser_code, re.IGNORECASE)
    
    utf8_decoded = False
    if valid_data_extracted:
        # Check if "Les Misérables" appears correctly in the first record
        first_rec_245 = str(parsed_json[0].get("245", ""))
        if "Misérables" in first_rec_245:
            utf8_decoded = True

    if encoding_fix_regex or utf8_decoded:
        score += 20
        feedback.append("[+] Bug 2 (Character Encoding) fixed (20/20)")
    else:
        feedback.append("[-] Bug 2 not fixed: Unicode strings not decoded accurately (0/20)")

    # 4. Check Bug 3: Subfield Delimiters (20 pts)
    # They need to split by \x1f instead of ^
    subfield_fix_regex = re.search(r'split\([\'"]\\x1f[\'"]\)', parser_code)
    
    subfields_clean = False
    if valid_data_extracted:
        first_rec_650 = str(parsed_json[0].get("650", ""))
        if "\\x1f" not in first_rec_650 and "^" not in first_rec_650:
            subfields_clean = True

    if subfield_fix_regex or subfields_clean:
        score += 20
        feedback.append("[+] Bug 3 (Subfield Delimiter Split) fixed (20/20)")
    else:
        feedback.append("[-] Bug 3 not fixed: Subfields still containing raw delimiters (0/20)")

    # 5. Check Bug 4: Repeatable Fields (20 pts)
    # They should use .append or lists instead of replacing the dictionary key
    repeatable_fix_regex = re.search(r'\.append\(|isinstance\(.*list\)', parser_code)
    
    repeatable_working = False
    if valid_data_extracted:
        first_rec_650 = parsed_json[0].get("650", [])
        if isinstance(first_rec_650, list) and len(first_rec_650) >= 2:
            repeatable_working = True

    if repeatable_fix_regex or repeatable_working:
        score += 20
        feedback.append("[+] Bug 4 (Repeatable Fields Data Loss) fixed (20/20)")
    else:
        feedback.append("[-] Bug 4 not fixed: Repeatable fields are still being overwritten (0/20)")

    # 6. VLM Trajectory Verification (20 pts)
    # Prove the agent actually interacted with VS Code and code execution
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_scr = get_final_screenshot(traj)
        if frames and final_scr:
            vlm_prompt = (
                "You are auditing a developer's trajectory. Based on these frames and the final screenshot, "
                "did the user edit python code inside VS Code and execute it in a terminal? "
                "Respond with exactly one word: YES or NO."
            )
            vlm_res = query_vlm(images=frames + [final_scr], prompt=vlm_prompt)
            if vlm_res and "YES" in vlm_res.get("parsed", {}).get("text", vlm_res.get("response", "")).upper():
                score += 20
                feedback.append("[+] VLM confirmed active interaction with code and terminal (20/20)")
            else:
                score += 5
                feedback.append("[-] VLM could not confidently confirm IDE usage and terminal execution (5/20)")
        else:
            feedback.append("[-] VLM skipped: Missing trajectory frames (0/20)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }