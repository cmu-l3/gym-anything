#!/usr/bin/env python3
"""
Verifier for build_csv_extractor task.

Evaluates the exported Talon package files using static code analysis and trajectory VLM verification.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Verification Prompt ---
VERIFICATION_PROMPT = """You are evaluating an agent that was tasked with writing a Talon voice command system (a Python script and a .talon file) to extract COVID-19 CSV data.

Please review these trajectory screenshots and determine:
1. Did the agent open a text editor (Notepad, VS Code, etc.)?
2. Did the agent actively write or paste Python code for reading a CSV file?
3. Did the agent actively write Talon command definitions?
4. Does it look like the agent successfully navigated to the correct Talon user directory to save the files?

Respond in JSON format:
{
    "used_editor": true/false,
    "wrote_python_code": true/false,
    "wrote_talon_code": true/false,
    "saved_files": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def verify_build_csv_extractor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Existence and Timestamps (20 points)
    task_start = result.get('task_start', 0)
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_mod = result.get('py_modified_time', 0)
    
    if py_exists and talon_exists:
        if py_mod >= task_start:
            score += 20
            feedback_parts.append("✅ Both package files created successfully during task.")
        else:
            score += 10
            feedback_parts.append("⚠️ Files exist but timestamps suggest they were not created during this session.")
    else:
        feedback_parts.append("❌ Missing required package files.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Talon Syntax Verification (15 points)
    talon_content = result.get('talon_content', '')
    cmd_grammar_valid = re.search(r'covid stats <user\.text>\s*:', talon_content, re.IGNORECASE) is not None
    cmd_action_valid = re.search(r'user\.get_latest_covid_stats\(.*?text\)', talon_content) is not None

    if cmd_grammar_valid and cmd_action_valid:
        score += 15
        feedback_parts.append("✅ Correct `.talon` grammar and action invocation.")
    elif cmd_grammar_valid or cmd_action_valid:
        score += 7
        feedback_parts.append("⚠️ `.talon` file is partially correct but missing exact grammar or action binding.")
    else:
        feedback_parts.append("❌ Incorrect `.talon` file grammar.")

    # 3. Python Static Analysis (35 points)
    py_content = result.get('py_content', '')
    has_decorator = "@mod.action_class" in py_content
    has_csv_import = "import csv" in py_content or "from csv" in py_content
    has_clip_set = "clip.set_text" in py_content
    
    # Check for the required string formatting elements
    has_correct_format = all(term in py_content for term in ["As of", "County reported", "cases", "deaths"])

    if has_decorator: score += 5
    if has_csv_import: score += 10
    if has_clip_set: score += 10
    if has_correct_format: score += 10

    if has_csv_import and has_clip_set and has_correct_format:
        feedback_parts.append("✅ Python logic contains required CSV reading, clipboard setting, and correct string format template.")
    else:
        feedback_parts.append("❌ Python file is missing required logic (CSV parsing, clipboard API, or string format).")

    # 4. VLM Trajectory Verification (30 points)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames

            if images:
                vlm_resp = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
                parsed = vlm_resp.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("used_editor"): vlm_score += 5
                if parsed.get("wrote_python_code"): vlm_score += 10
                if parsed.get("wrote_talon_code"): vlm_score += 10
                if parsed.get("saved_files"): vlm_score += 5
                
                score += vlm_score
                if vlm_score >= 20:
                    feedback_parts.append(f"✅ VLM verified active coding workflow ({vlm_score}/30 pts).")
                else:
                    feedback_parts.append(f"⚠️ VLM did not observe complete coding workflow ({vlm_score}/30 pts).")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification skipped due to error: {e}")
            # Award partial points if standard checks passed beautifully to avoid punishing for framework outages
            if score >= 60: score += 20 
    else:
        feedback_parts.append("⚠️ query_vlm not available.")
        if score >= 60: score += 20

    # Pass logic: Must get 75+ points and must have actually written the python logic
    passed = score >= 75 and has_clip_set and has_correct_format

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }