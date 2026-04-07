#!/usr/bin/env python3
"""
Verifier for create_transcription_assistant task.

VERIFICATION STRATEGY:
1. Programmatic State Check: Verify the correct files were created and modified DURING the task.
2. AST Parsing: Statically analyze transcription.py to ensure the module defines the 4 requested actions using correct Talon Python API calls.
3. Syntax Regex: Check transcription.talon mapping matches.
4. VLM Verification (Trajectory): Prove the agent typed the implementation and didn't cheat.
"""

import json
import os
import ast
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully created a Talon Voice transcription assistant module.

Review these trajectory frames and determine:
1. Did the agent open a text editor (like Notepad or VS Code) and write/edit Python code (`transcription.py`)?
2. Did the agent write/edit Talon configuration code (`transcription.talon`)?
3. Can you visually verify that the code implements speaker labels, timecodes, or media play/pause?
4. Is there evidence the agent actually typed this (progression of text) rather than just pasting it instantaneously from nowhere?

Respond in JSON format:
{
    "edited_python": true/false,
    "edited_talon_file": true/false,
    "implemented_transcription_logic": true/false,
    "showed_work_progression": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def check_talon_cmd(content, pattern):
    """Safely match a regex pattern inside the .talon content."""
    return bool(re.search(pattern, content, re.IGNORECASE))

def verify_create_transcription_assistant(traj, env_info, task_info):
    """Primary entry point for verifying the transcription assistant."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    feedback_parts = []
    score = 0
    max_score = 100

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')

    try:
        # Copy result JSON
        copy_from_env("C:\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        py_exists = result.get('py_exists', False)
        talon_exists = result.get('talon_exists', False)
        task_start = result.get('task_start', 0)
        
        # 1. Check File Creation and Anti-Gaming Timestamps (10 points)
        py_valid = py_exists and result.get('py_mtime', 0) >= task_start
        talon_valid = talon_exists and result.get('talon_mtime', 0) >= task_start

        if py_valid and talon_valid:
            score += 10
            feedback_parts.append("Both files successfully created/modified during task.")
        else:
            feedback_parts.append(f"Missing or stale files. Python valid: {py_valid}, Talon valid: {talon_valid}.")
            if not py_exists and not talon_exists:
                return {"passed": False, "score": 0, "feedback": "Files not found. " + " | ".join(feedback_parts)}

        # 2. Python AST Parsing (45 points total)
        py_content = ""
        if py_exists:
            copy_from_env("C:\\Temp\\transcription.py", temp_py.name)
            with open(temp_py.name, 'r', encoding='utf-8', errors='ignore') as f:
                py_content = f.read()

            # Base Syntax Check (10 points)
            try:
                tree = ast.parse(py_content)
                score += 10
                feedback_parts.append("Python AST parsed successfully.")
            except SyntaxError:
                tree = None
                feedback_parts.append("Python SyntaxError detected.")

            if tree:
                # Speaker Label Logic (15 points)
                if 'insert_speaker_label' in py_content and ('upper' in py_content) and ('actions.insert' in py_content):
                    score += 15
                    feedback_parts.append("Speaker label logic detected.")
                else:
                    feedback_parts.append("Missing speaker label formatting logic.")

                # Timecode Logic (10 points)
                if 'insert_current_timecode' in py_content and ('datetime' in py_content) and ('actions.insert' in py_content):
                    score += 10
                    feedback_parts.append("Timecode logic detected.")
                else:
                    feedback_parts.append("Missing or hardcoded timecode logic.")

                # Media Actions Logic (10 points)
                has_play = 'toggle_and_mark' in py_content and ('play_pause' in py_content) and ('sleep' in py_content)
                has_rewind = 'rewind_audio' in py_content and ('left:5' in py_content)
                if has_play and has_rewind:
                    score += 10
                    feedback_parts.append("Media control logic detected.")
                else:
                    feedback_parts.append("Missing media control keys ('play_pause' or 'left:5').")

        # 3. Talon Command File Validation (25 points)
        if talon_exists:
            copy_from_env("C:\\Temp\\transcription.talon", temp_talon.name)
            with open(temp_talon.name, 'r', encoding='utf-8', errors='ignore') as f:
                talon_content = f.read()

            criteria_met = 0
            # Allow flexible mapping formats
            if check_talon_cmd(talon_content, r"speaker <user\.text>\$?\s*:\s*(?:user\.)?insert_speaker_label"):
                criteria_met += 1
            if check_talon_cmd(talon_content, r"mark time\s*:\s*(?:user\.)?insert_current_timecode"):
                criteria_met += 1
            if check_talon_cmd(talon_content, r"halt and mark\s*:\s*(?:user\.)?toggle_and_mark"):
                criteria_met += 1
            if check_talon_cmd(talon_content, r"audio rewind\s*:\s*(?:user\.)?rewind_audio"):
                criteria_met += 1
            
            talon_score = int((criteria_met / 4.0) * 25)
            score += talon_score
            feedback_parts.append(f"Talon commands mapped: {criteria_met}/4.")

        # 4. VLM Trajectory Verification (20 points)
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_criteria = sum([
                parsed.get("edited_python", False),
                parsed.get("edited_talon_file", False),
                parsed.get("implemented_transcription_logic", False),
                parsed.get("showed_work_progression", False)
            ])
            
            confidence = parsed.get("confidence", "low")
            multiplier = {"high": 1.0, "medium": 0.8, "low": 0.5}.get(confidence.lower(), 0.5)
            
            vlm_score = int((vlm_criteria / 4.0) * 20 * multiplier)
            score += vlm_score
            feedback_parts.append(f"VLM Trajectory score: {vlm_score}/20.")
        else:
            feedback_parts.append("VLM verification failed to process.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verifier exception: {e}"}
        
    finally:
        for tmp_file in [temp_result.name, temp_py.name, temp_talon.name]:
            if os.path.exists(tmp_file):
                try:
                    os.unlink(tmp_file)
                except:
                    pass

    # Success conditions: Minimum 70 points AND the base files were created/modified
    passed = score >= 70 and py_valid and talon_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }