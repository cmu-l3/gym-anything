#!/usr/bin/env python3
import json
import os
import tempfile

def verify_longitudinal_wave_adaptation(traj, env_info, task_info):
    """
    Verifies that the agent correctly adapted the survey for Wave 2.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criteria 1: Survey Created (10 pts)
    if result.get("survey_found"):
        score += 10
        feedback.append("Wave 2 survey created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Wave 2 survey not found."}

    # Criteria 2: Demographics Group Removed (25 pts)
    # The agent should have deleted this group.
    if not result.get("demog_group_exists"):
        score += 25
        feedback.append("Baseline Demographics group correctly removed.")
    else:
        feedback.append("Baseline Demographics group was NOT removed.")

    # Criteria 3: Original Groups/Questions Preserved (30 pts)
    # This verifies the agent COPIED the survey rather than creating a new empty one.
    # We check if School/Family groups exist AND if the GPA question (from Wave 1) is present.
    preserved = (
        result.get("school_group_exists") and 
        result.get("family_group_exists") and 
        result.get("gpa_question_exists")
    )
    if preserved:
        score += 30
        feedback.append("Original structure (School/Family/GPA) preserved.")
    else:
        feedback.append("Original structure missing. Did you copy Wave 1?")

    # Criteria 4: New Content Added (25 pts)
    # Check for 'Recent Changes' group and 'moved' question.
    new_content = (
        result.get("recent_group_exists") and 
        result.get("moved_question_exists")
    )
    if new_content:
        # Check Question Type (Y for Yes/No)
        q_type = result.get("moved_question_type", "")
        if q_type == "Y":
            score += 25
            feedback.append("New group and Yes/No question added correctly.")
        else:
            score += 15 # Partial credit if question exists but wrong type
            feedback.append(f"New question added but type is '{q_type}' (expected Yes/No 'Y').")
    else:
        feedback.append("New 'Recent Changes' group or 'moved' question missing.")

    # Criteria 5: Activated (10 pts)
    if result.get("survey_active"):
        score += 10
        feedback.append("Survey activated.")
    else:
        feedback.append("Survey not activated.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }