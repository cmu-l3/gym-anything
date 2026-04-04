#!/usr/bin/env python3
"""
Verifier for technical_manual_master_compile task.
Verifies the creation of an OpenOffice Master Document (.odm) with correctly linked chapters.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_technical_manual_master_compile(traj, env_info, task_info):
    """
    Verifies that the agent created a valid Master Document linking the 5 chapters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Gate: File Existence (20 pts)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Master document 'AeroTurbine_Master.odm' was not created."
        }
    score += 20
    feedback.append("File created successfully.")

    # Anti-gaming check
    if not result.get("file_created_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "File timestamp indicates it was not created during the task session."
        }

    # 2. Format Check (10 pts)
    if result.get("is_odm_format", False):
        score += 10
        feedback.append("Correct Master Document format detected.")
    else:
        feedback.append("Warning: File format does not appear to be a standard Master Document (mimetype check).")

    # 3. Linked Chapters Check (40 pts)
    link_count = result.get("link_count", 0)
    linked_files = result.get("linked_files", [])
    
    if link_count == 5:
        score += 40
        feedback.append("All 5 chapters are linked.")
    elif link_count > 0:
        partial = link_count * 8
        score += partial
        feedback.append(f"Found {link_count}/5 linked chapters.")
    else:
        feedback.append("No linked chapters found. Did you copy-paste text instead of linking files?")

    # 4. Link Order Check (10 pts)
    # Check if links contain 01, 02, 03, 04, 05 in that order
    if link_count >= 5:
        correct_order = True
        for i, expected in enumerate(["01", "02", "03", "04", "05"]):
            if expected not in linked_files[i]:
                correct_order = False
                break
        
        if correct_order:
            score += 10
            feedback.append("Chapters are in correct numerical order.")
        else:
            feedback.append("Chapters are not in correct numerical order.")

    # 5. Table of Contents (10 pts)
    if result.get("has_toc", False):
        score += 10
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Table of Contents missing.")

    # 6. Title Check (10 pts)
    if result.get("has_title", False):
        score += 10
        feedback.append("Title text found.")
    else:
        feedback.append("Title 'AeroTurbine 500-X Operator Manual' not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }