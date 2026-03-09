#!/usr/bin/env python3
"""
Verifier for create_work_item_template task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_work_item_template(traj, env_info, task_info):
    """
    Verify that the 'Frontend Bug Report' template was created with correct fields.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define paths
    # Note: Windows path in the VM, accessible via copy_from_env
    remote_path = r"C:\Users\Docker\task_results\template_result.json"
    
    # 1. Fetch result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_file.close()
    
    try:
        copy_from_env(remote_path, temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task results. Did the export script run?"
        }

    # 2. Load JSON
    try:
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    finally:
        os.unlink(temp_file.name)

    # 3. Score the result
    score = 0
    feedback = []
    
    # Check 1: Template exists (20 pts)
    if not result.get("template_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Template 'Frontend Bug Report' was not found in the team templates."
        }
    score += 20
    feedback.append("Template created successfully.")

    # Check 2: Work Item Type (10 pts)
    actual_type = result.get("work_item_type", "")
    if actual_type == "Bug":
        score += 10
        feedback.append("Correct work item type (Bug).")
    else:
        feedback.append(f"Wrong work item type: expected 'Bug', got '{actual_type}'.")

    # Get fields for detailed checking
    fields = result.get("fields", {})

    # Check 3: Priority (10 pts)
    # Field: Microsoft.VSTS.Common.Priority
    prio = fields.get("Microsoft.VSTS.Common.Priority", "")
    if prio == "2" or prio == 2:
        score += 10
        feedback.append("Priority correctly set to 2.")
    else:
        feedback.append(f"Priority incorrect: got '{prio}'.")

    # Check 4: Severity (10 pts)
    # Field: Microsoft.VSTS.Common.Severity
    severity = fields.get("Microsoft.VSTS.Common.Severity", "")
    if "2 - High" in str(severity):
        score += 10
        feedback.append("Severity correctly set to 2 - High.")
    else:
        feedback.append(f"Severity incorrect: got '{severity}'.")

    # Check 5: Area Path (10 pts)
    # Field: System.AreaPath
    area = fields.get("System.AreaPath", "")
    if "TailwindTraders" in area:
        score += 10
        feedback.append("Area Path correctly set.")
    else:
        feedback.append(f"Area Path incorrect: got '{area}'.")

    # Check 6: Tags (20 pts)
    # Field: System.Tags (semicolon usually, but JSON might be string)
    tags_raw = fields.get("System.Tags", "")
    # Tags can be "frontend; needs-triage"
    tags_lower = str(tags_raw).lower()
    
    tag_score = 0
    if "frontend" in tags_lower:
        tag_score += 10
    if "needs-triage" in tags_lower:
        tag_score += 10
    
    score += tag_score
    if tag_score == 20:
        feedback.append("Tags correctly set.")
    elif tag_score > 0:
        feedback.append(f"Tags partially correct: got '{tags_raw}'.")
    else:
        feedback.append(f"Tags incorrect: got '{tags_raw}'.")

    # Check 7: Repro Steps / Description (20 pts)
    # Field: Microsoft.VSTS.TCM.ReproSteps OR System.Description
    repro = fields.get("Microsoft.VSTS.TCM.ReproSteps", "")
    desc = fields.get("System.Description", "")
    content = (str(repro) + str(desc)).lower()
    
    required_phrases = ["steps to reproduce", "expected result"]
    phrases_found = [p for p in required_phrases if p in content]
    
    if len(phrases_found) == len(required_phrases):
        score += 20
        feedback.append("Repro steps template structure is correct.")
    else:
        feedback.append("Repro steps missing required sections (Steps to Reproduce, Expected Result).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }