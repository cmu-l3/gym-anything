#!/usr/bin/env python3
"""
Verifier for transcribe_meeting_whiteboard task.

Checks:
1. Note document exists (20 pts)
2. Note contains the specific dynamically generated project code (50 pts)
3. Note contains context keywords from the whiteboard (20 pts)
4. Anti-gaming: Note was created during task session (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transcribe_meeting_whiteboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    note_found = result.get("note_found", False)
    note_content = result.get("note_content", "") or ""
    ground_truth_code = result.get("ground_truth_code", "UNKNOWN_CODE")
    was_created = result.get("was_created_during_task", False)

    score = 0
    feedback_parts = []
    passed = False

    # Criterion 1: Note Exists (20 pts)
    if note_found:
        score += 20
        feedback_parts.append("Note 'Strategy Meeting Notes' created.")
    else:
        feedback_parts.append("Note 'Strategy Meeting Notes' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Anti-gaming (10 pts)
    if was_created:
        score += 10
    else:
        feedback_parts.append("Warning: Note timestamp suggests it wasn't created in this session.")

    # Criterion 3: Project Code Match (50 pts)
    # The code (e.g., PROJ-8374) must be present in the content
    if ground_truth_code in note_content:
        score += 50
        feedback_parts.append(f"Correct Project Code ({ground_truth_code}) found.")
    else:
        feedback_parts.append(f"Project Code ({ground_truth_code}) missing from note.")
        # Check for near misses or partials
        if "PROJ" in note_content:
            feedback_parts.append("(Found 'PROJ' prefix but number likely wrong).")

    # Criterion 4: Context Keywords (20 pts)
    # Keywords visible in the setup_task image generation: "Budget", "Backend", "Launch", "Beta"
    keywords = ["Budget", "Backend", "Launch", "Beta", "Strategy"]
    found_keywords = [kw for kw in keywords if kw.lower() in note_content.lower()]
    
    if len(found_keywords) >= 2:
        score += 20
        feedback_parts.append(f"Context captured ({len(found_keywords)} keywords found).")
    elif len(found_keywords) == 1:
        score += 10
        feedback_parts.append("Minimal context captured.")
    else:
        feedback_parts.append("Missing context keywords (Budget, Launch, etc.).")

    # Final Pass Decision
    # Must have Note + Code to pass (Min 70 pts)
    if note_found and (ground_truth_code in note_content):
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }