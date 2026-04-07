#!/usr/bin/env python3
"""Verifier for Create Resource Folder task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_resource_folder(traj, env_info, task_info):
    """
    Verify creation of a Folder resource with specific files and settings.

    Scoring (100 points):
    - Folder exists in BIO101 (25 points)
    - Syllabus_Supplement.txt uploaded (25 points)
    - Lab_Safety_Checklist.txt uploaded (25 points)
    - Display mode set to 'On a separate page' (15 points)
    - Show download button enabled (10 points)
    
    Anti-gaming/Penalty:
    - Files must be newly created/uploaded during task window.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_resource_folder_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}
        
        # 1. Check Folder Existence (25 pts)
        folder_found = result.get('folder_found', False)
        folder_name = result.get('folder_name', '')
        
        if folder_found:
            score += 25
            subscores["folder_exists"] = True
            feedback_parts.append(f"Folder '{folder_name}' created")
        else:
            subscores["folder_exists"] = False
            feedback_parts.append("Folder not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # 2. Check File 1: Syllabus (25 pts)
        syllabus_exists = result.get('file_syllabus_exists', False)
        if syllabus_exists:
            score += 25
            subscores["syllabus_uploaded"] = True
            feedback_parts.append("Syllabus uploaded")
        else:
            subscores["syllabus_uploaded"] = False
            feedback_parts.append("Syllabus missing")

        # 3. Check File 2: Lab Checklist (25 pts)
        lab_exists = result.get('file_lab_exists', False)
        if lab_exists:
            score += 25
            subscores["lab_uploaded"] = True
            feedback_parts.append("Lab Checklist uploaded")
        else:
            subscores["lab_uploaded"] = False
            feedback_parts.append("Lab Checklist missing")

        # 4. Check Display Mode (15 pts)
        # Expected: 1 (On a separate page). 0 is Inline.
        display_mode = int(result.get('display_mode', -1))
        if display_mode == 1:
            score += 15
            subscores["display_mode_correct"] = True
            feedback_parts.append("Display mode correct (Separate page)")
        else:
            subscores["display_mode_correct"] = False
            feedback_parts.append(f"Display mode incorrect (Got {display_mode}, expected 1)")

        # 5. Check Download Button (10 pts)
        # Expected: 1 (Yes/Checked)
        show_download = int(result.get('show_download', -1))
        if show_download == 1:
            score += 10
            subscores["download_btn_correct"] = True
            feedback_parts.append("Download button enabled")
        else:
            subscores["download_btn_correct"] = False
            feedback_parts.append("Download button disabled")

        # Anti-gaming timestamp check
        task_start = int(result.get('task_start_time', 0))
        folder_time = int(result.get('timemodified', 0))
        
        if folder_time < task_start:
            score = 0
            feedback_parts.append("FAIL: Folder creation timestamp predates task start (pre-existing)")

        # Final Pass/Fail
        # Threshold: 75 points (Folder + Both Files required)
        passed = score >= 75

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}