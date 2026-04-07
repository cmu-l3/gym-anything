#!/usr/bin/env python3
"""
Verifier for create_regex_builder task.

Verification Strategy:
1. File System Check: Verifies all expected Talon and Python scripts exist and were modified during the task.
2. Content Analysis: Parses the .py, .talon, and .talon-list files to ensure they contain correct syntax and mappings.
3. Execution Outcome: Evaluates ips.txt for exact expected real-world IPv4 matches.
4. Trajectory VLM: Uses sampled frames to visually confirm coding activity, avoiding spoofed final screens.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_regex_builder(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get('metadata', {})
    expected_ips = set(metadata.get('expected_ips', []))

    # Retrieve result JSON from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get("task_start", 0)
    files_state = result.get("files", {})

    score = 0
    feedback_parts = []
    
    # Define file keys matching the PS script
    setup_py = "C:\\Users\\Docker\\AppData\\Roaming\\talon\\user\\forensic_regex\\regex_setup.py"
    talon_list = "C:\\Users\\Docker\\AppData\\Roaming\\talon\\user\\forensic_regex\\regex.talon-list"
    talon_cmd = "C:\\Users\\Docker\\AppData\\Roaming\\talon\\user\\forensic_regex\\regex.talon"
    extract_py = "C:\\Users\\Docker\\Desktop\\Forensics\\extract_ips.py"
    ips_txt = "C:\\Users\\Docker\\Desktop\\Forensics\\ips.txt"

    # CRITERION 1: Talon Python Module Setup (15 pts)
    f_setup = files_state.get(setup_py, {})
    if f_setup.get("exists") and f_setup.get("mtime", 0) >= task_start:
        content = f_setup.get("content", "")
        if "Module(" in content and "regex_class" in content and "mod.list" in content:
            score += 15
            feedback_parts.append("✅ regex_setup.py created correctly")
        else:
            score += 5
            feedback_parts.append("❌ regex_setup.py exists but missing Module/list declarations")
    else:
        feedback_parts.append("❌ regex_setup.py not found or not modified")

    # CRITERION 2: Talon List Mappings (20 pts)
    f_list = files_state.get(talon_list, {})
    if f_list.get("exists") and f_list.get("mtime", 0) >= task_start:
        content = f_list.get("content", "")
        mappings = [
            r"digit:\s*\\d",
            r"word char:\s*\\w",
            r"whitespace:\s*\\s",
            r"boundary:\s*\\b",
            r"any char:\s*\.",
            r"start:\s*\^",
            r"end:\s*\$"
        ]
        import re
        matches = sum(1 for m in mappings if re.search(m, content))
        if "user.regex_class" in content:
            score += 5
        score += (matches / 7.0) * 15
        if matches == 7:
            feedback_parts.append("✅ regex.talon-list mappings correct")
        else:
            feedback_parts.append(f"⚠️ regex.talon-list partial mappings ({matches}/7)")
    else:
        feedback_parts.append("❌ regex.talon-list not found")

    # CRITERION 3: Talon Command File (15 pts)
    f_cmd = files_state.get(talon_cmd, {})
    if f_cmd.get("exists") and f_cmd.get("mtime", 0) >= task_start:
        content = f_cmd.get("content", "")
        if "rx <user.regex_class>" in content and "insert" in content:
            score += 15
            feedback_parts.append("✅ regex.talon commands defined correctly")
        else:
            score += 5
            feedback_parts.append("❌ regex.talon exists but missing correct command syntax")
    else:
        feedback_parts.append("❌ regex.talon not found")

    # CRITERION 4: Extraction Python Script (15 pts)
    f_extract = files_state.get(extract_py, {})
    if f_extract.get("exists") and f_extract.get("mtime", 0) >= task_start:
        content = f_extract.get("content", "")
        if "import re" in content and "auth.log" in content and "ips.txt" in content:
            score += 15
            feedback_parts.append("✅ extract_ips.py created and appears valid")
        else:
            score += 5
            feedback_parts.append("⚠️ extract_ips.py exists but lacks required components")
    else:
        feedback_parts.append("❌ extract_ips.py not found")

    # CRITERION 5: Output Execution & Ground Truth Data Matching (15 pts)
    f_ips = files_state.get(ips_txt, {})
    if f_ips.get("exists") and f_ips.get("mtime", 0) >= task_start:
        content = f_ips.get("content", "")
        # Extract IPs line by line and ignore empty lines/whitespace
        extracted_ips = set(line.strip() for line in content.splitlines() if line.strip())
        
        if extracted_ips == expected_ips:
            score += 15
            feedback_parts.append("✅ ips.txt contains perfect matches for expected IP data")
        else:
            intersection = expected_ips.intersection(extracted_ips)
            score += int((len(intersection) / len(expected_ips)) * 10)
            feedback_parts.append(f"⚠️ ips.txt contains partial matches ({len(intersection)}/{len(expected_ips)} expected IPs)")
    else:
        feedback_parts.append("❌ ips.txt not found (script likely wasn't executed or failed)")

    # CRITERION 6: VLM Verification of coding activity (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Look at these screenshots from a computer session. Did the user:
            1. Open a text editor or IDE (Notepad, VS Code, etc.)?
            2. Write configuration files or Python code?
            Respond in JSON: {"coding_visible": true/false}
            """
            
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result.get("success") and vlm_result.get("parsed", {}).get("coding_visible", False):
                score += 20
                feedback_parts.append("✅ VLM confirmed visible coding workflow")
            else:
                feedback_parts.append("❌ VLM could not confirm text editor usage")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("⚠️ VLM verification skipped due to error")

    passed = score >= 70 and f_ips.get("exists", False) and f_setup.get("exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }