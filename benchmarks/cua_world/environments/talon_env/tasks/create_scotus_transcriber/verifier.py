#!/usr/bin/env python3
"""
Verifier for create_scotus_transcriber task.

VERIFICATION STRATEGY:
1. Ensure output files exist and were created during task.
2. Programmatically verify logic in transcriber.py (JSON parsing, string formatting, datetimes).
3. Programmatically verify Talon command syntax in transcriber.talon.
4. Utilize VLM Trajectory to confirm authentic text editor workflow.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_scotus_transcriber(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Temp files for pulling data from Windows environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')

    try:
        # Pull execution metadata
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result metadata: {e}"}

        # ---------------------------------------------------------
        # CRITERION 1: File Existence & Anti-Gaming (15 points)
        # ---------------------------------------------------------
        if result.get('py_exists') and result.get('talon_exists') and result.get('json_exists'):
            if result.get('py_created_during_task'):
                score += 15
                feedback_parts.append("✅ All required files created during task")
            else:
                feedback_parts.append("❌ Files existed before task (Anti-gaming check failed)")
                return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        else:
            feedback_parts.append("❌ Missing one or more required files (JSON, PY, or TALON)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Pull Python and Talon files for static analysis
        py_content = ""
        talon_content = ""
        
        copy_from_env("C:\\Users\\Docker\\AppData\\Roaming\\talon\\user\\scotus_transcriber\\transcriber.py", temp_py.name)
        with open(temp_py.name, 'r', encoding='utf-8', errors='ignore') as f:
            py_content = f.read()

        copy_from_env("C:\\Users\\Docker\\AppData\\Roaming\\talon\\user\\scotus_transcriber\\transcriber.talon", temp_talon.name)
        with open(temp_talon.name, 'r', encoding='utf-8', errors='ignore') as f:
            talon_content = f.read()

        # ---------------------------------------------------------
        # CRITERION 2: JSON Parsing Logic (15 points)
        # ---------------------------------------------------------
        has_json_load = 'json.load' in py_content
        if has_json_load:
            score += 15
            feedback_parts.append("✅ JSON parsing logic found")
        else:
            feedback_parts.append("❌ JSON parsing logic missing (hardcoded values?)")

        # ---------------------------------------------------------
        # CRITERION 3: String Formatting for Dict Keys (15 points)
        # ---------------------------------------------------------
        has_lower = '.lower()' in py_content or 'lower' in py_content
        has_replace = '.replace(' in py_content or 're.sub(' in py_content or 'translate(' in py_content
        if has_lower and has_replace:
            score += 15
            feedback_parts.append("✅ Spoken list key formatting logic found")
        else:
            feedback_parts.append("⚠️ List key formatting logic incomplete")

        # ---------------------------------------------------------
        # CRITERION 4: State Management & Output Generation (15 points)
        # ---------------------------------------------------------
        has_state = 'active_speaker' in py_content or 'global' in py_content or 'self.' in py_content
        has_datetime = 'datetime' in py_content or 'time.' in py_content
        has_output_fmt = 'f"' in py_content or "f'" in py_content or '.format(' in py_content or '%s' in py_content

        if has_state and has_datetime and has_output_fmt:
            score += 15
            feedback_parts.append("✅ State management, datetime, and string formatting logic found")
        else:
            feedback_parts.append("❌ Missing State, Datetime, or Output Formatting logic")

        # ---------------------------------------------------------
        # CRITERION 5: Talon Commands (15 points)
        # ---------------------------------------------------------
        has_speaker_cmd = re.search(r'speaker\s+(<[\w\.]+>|\{[\w\.]+\})', talon_content, re.IGNORECASE)
        has_record_cmd = re.search(r'record\s+<[\w\.]+>', talon_content, re.IGNORECASE)
        
        if has_speaker_cmd and has_record_cmd:
            score += 15
            feedback_parts.append("✅ Talon voice commands defined correctly")
        else:
            feedback_parts.append("❌ Missing required Talon voice commands mapping")

        # ---------------------------------------------------------
        # CRITERION 6: VLM Trajectory Verification (25 points)
        # ---------------------------------------------------------
        try:
            from gym_anything.vlm import sample_trajectory_frames
            query_vlm = env_info.get('query_vlm')
            
            if query_vlm:
                frames = sample_trajectory_frames(traj, n=5)
                vlm_prompt = (
                    "You are verifying a Talon Voice configuration task. "
                    "Did the agent use a text editor or IDE (like Notepad, VS Code, or PowerShell) to write Python (.py) and Talon (.talon) code? "
                    "Look for evidence of editing code related to 'scotus_advocates', 'active_speaker', and JSON parsing. "
                    "Respond in JSON format: {\"wrote_code\": true/false, \"confidence\": \"high\"/\"medium\"/\"low\"}"
                )
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                
                if vlm_result.get("success") and vlm_result.get("parsed", {}).get("wrote_code", False):
                    score += 25
                    feedback_parts.append("✅ VLM verified active coding workflow")
                else:
                    feedback_parts.append("❌ VLM did not verify code writing workflow")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("⚠️ VLM check skipped or failed")

        # Determine success threshold
        key_criteria = result.get('py_created_during_task') and has_json_load and has_datetime
        passed = (score >= 60) and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Clean up temporary files
        for f in [temp_result, temp_py, temp_talon]:
            if os.path.exists(f.name):
                try:
                    os.unlink(f.name)
                except Exception:
                    pass