#!/usr/bin/env python3
"""Verifier for Upload SCORM Training Module task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_upload_scorm(traj, env_info, task_info):
    """
    Verify that the SCORM package was uploaded and configured correctly.

    Scoring (100 points):
    - Criterion 1: SCORM activity exists in FIRE101 and created during task (25 points)
    - Criterion 2: Activity name matches expected (15 points)
    - Criterion 3: Package file uploaded (20 points)
    - Criterion 4: Grading method = Highest grade (1) (15 points)
    - Criterion 5: Max attempts = 3 (15 points)
    - Criterion 6: Created after task start (Anti-gaming) (10 points)

    Pass threshold: 60 points (Must include existence + package upload)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_activity_name = metadata.get('activity_name', "Fire Safety Certification - Module 1")
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/upload_scorm_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract data
        scorm_found = result.get('scorm_found', False)
        activity = result.get('activity', {})
        task_start = int(result.get('task_start_timestamp', 0))
        timemodified = int(activity.get('timemodified', 0))
        
        # Check timestamps for anti-gaming
        created_during_task = timemodified >= task_start
        
        # Criterion 1: Existence & Timing (25 points + 10 points)
        if scorm_found:
            score += 25
            feedback_parts.append("SCORM activity found")
            
            if created_during_task:
                score += 10
                feedback_parts.append("Created during task session")
            else:
                feedback_parts.append("FAIL: Activity existed before task started")
        else:
            feedback_parts.append("No SCORM activity found")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No SCORM activity found in course",
                "subscores": {"exists": False}
            }

        # Criterion 2: Name match (15 points)
        name = activity.get('name', '')
        # Allow partial match or case-insensitive
        if expected_activity_name.lower() in name.lower():
            score += 15
            subscores["name_match"] = True
            feedback_parts.append("Activity name correct")
        else:
            subscores["name_match"] = False
            feedback_parts.append(f"Name mismatch (Expected: '{expected_activity_name}', Got: '{name}')")

        # Criterion 3: Package Uploaded (20 points)
        reference = activity.get('reference', '')
        file_uploaded = result.get('file_uploaded', False)
        
        if file_uploaded and reference:
            score += 20
            subscores["package_uploaded"] = True
            feedback_parts.append(f"Package uploaded ({reference})")
        else:
            subscores["package_uploaded"] = False
            feedback_parts.append("No package file uploaded")

        # Criterion 4: Grading Method (15 points)
        # 1 = Highest grade
        grademethod = int(activity.get('grademethod', -1))
        if grademethod == 1:
            score += 15
            subscores["grademethod"] = True
            feedback_parts.append("Grading method: Highest grade")
        else:
            subscores["grademethod"] = False
            feedback_parts.append(f"Wrong grading method (Got: {grademethod}, Expected: 1)")

        # Criterion 5: Max Attempts (15 points)
        maxattempt = int(activity.get('maxattempt', -1))
        if maxattempt == 3:
            score += 15
            subscores["maxattempt"] = True
            feedback_parts.append("Max attempts: 3")
        else:
            subscores["maxattempt"] = False
            feedback_parts.append(f"Wrong max attempts (Got: {maxattempt}, Expected: 3)")

        # Pass logic
        # Must exist, be new, and have a package uploaded
        critical_success = scorm_found and created_during_task and subscores.get("package_uploaded", False)
        passed = (score >= 60) and critical_success

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}