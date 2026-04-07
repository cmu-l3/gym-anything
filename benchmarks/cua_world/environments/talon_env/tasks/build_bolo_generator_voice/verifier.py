#!/usr/bin/env python3
"""
Verifier for build_bolo_generator_voice task.
Evaluates proper creation of multiple interconnected Talon configuration files
and utilizes VLM to verify actual editor usage.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_bolo_generator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Retrieve the exported JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Anti-Gaming Check
    if not result.get('files_created_during_task', False):
        feedback.append("Failed: Files were not created or modified during the task execution.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    
    score += 15
    feedback.append("Files created within task window.")

    # 3. Fetch file contents securely
    files_to_check = ['makes.talon-list', 'colors.talon-list', 'bolo.py', 'bolo.talon']
    file_contents = {}
    
    for fname in files_to_check:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            # File may not exist, so exception catching is expected
            copy_from_env(f"C:/temp/export/{fname}", temp_file.name)
            with open(temp_file.name, 'r', encoding='utf-8') as f:
                file_contents[fname] = f.read()
        except Exception:
            file_contents[fname] = None
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

    # 4. Content Verification - makes.talon-list
    makes_content = file_contents.get('makes.talon-list', '')
    if makes_content and 'list: user.ncic_vehicle_make' in makes_content and 'toyota' in makes_content.lower():
        score += 15
        feedback.append("makes.talon-list configured correctly.")
    else:
        feedback.append("makes.talon-list is missing or incorrect.")

    # 5. Content Verification - colors.talon-list
    colors_content = file_contents.get('colors.talon-list', '')
    if colors_content and 'list: user.ncic_vehicle_color' in colors_content and 'red' in colors_content.lower():
        score += 15
        feedback.append("colors.talon-list configured correctly.")
    else:
        feedback.append("colors.talon-list is missing or incorrect.")

    # 6. Content Verification - bolo.py
    py_content = file_contents.get('bolo.py', '')
    if py_content:
        has_module = 'Module(' in py_content or 'talon import' in py_content
        has_lists = 'ncic_vehicle_make' in py_content and 'ncic_vehicle_color' in py_content
        has_action = 'def generate_bolo' in py_content
        has_string = 'BOLO ALERT: Suspect vehicle is a' in py_content
        
        if has_module and has_lists and has_action and has_string:
            score += 30
            feedback.append("bolo.py Python logic verified.")
        else:
            feedback.append("bolo.py is missing required Talon module elements or the specific format string.")
    else:
        feedback.append("bolo.py is missing.")

    # 7. Content Verification - bolo.talon
    talon_content = file_contents.get('bolo.talon', '')
    if talon_content:
        has_color_capture = 'user.ncic_vehicle_color' in talon_content
        has_make_capture = 'user.ncic_vehicle_make' in talon_content
        has_action_call = 'generate_bolo' in talon_content
        
        if has_color_capture and has_make_capture and has_action_call:
            score += 10
            feedback.append("bolo.talon command mappings verified.")
        else:
            feedback.append("bolo.talon missing required captures or action calls.")
    else:
        feedback.append("bolo.talon is missing.")

    # 8. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = """Analyze these trajectory frames of a computer agent setting up voice commands.
                Did the agent open a text editor (like Notepad or VS Code) and type/edit the required configuration code files?
                Respond strictly in JSON format:
                {"used_editor": true/false}
                """
                vlm_res = query_vlm(images=frames, prompt=prompt)
                
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_editor', False):
                        vlm_score = 15
                        feedback.append("VLM verified text editor usage during trajectory.")
                    else:
                        feedback.append("VLM did not observe text editor usage.")
                else:
                    logger.warning(f"VLM query failed: {vlm_res.get('error')}")
        except Exception as e:
            logger.error(f"Failed during VLM evaluation: {e}")
    else:
        logger.warning("query_vlm function not provided. Skipping VLM check.")
        # If VLM is unavailable, award points if file checks passed exceptionally well
        if score >= 85:
            vlm_score = 15

    score += vlm_score

    # Final Evaluation Threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }