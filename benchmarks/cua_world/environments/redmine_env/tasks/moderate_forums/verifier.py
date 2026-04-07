#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_moderate_forums(traj, env_info, task_info):
    """
    Verifies the moderate_forums task.
    
    Scoring:
    - 25 pts: "Technical Q&A" board exists
    - 10 pts: Board description matches exactly
    - 35 pts: Technical thread moved to new board
    - 30 pts: Old thread locked
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    db_state = result.get('db_state', {})
    
    score = 0
    feedback = []

    # Criterion 1: Board Creation (25 pts)
    if db_state.get('technical_board_exists'):
        score += 25
        feedback.append("New board 'Technical Q&A' created.")
    else:
        feedback.append("New board 'Technical Q&A' NOT found.")

    # Criterion 2: Board Description (10 pts)
    if db_state.get('technical_board_desc_correct'):
        score += 10
        feedback.append("Board description correct.")
    elif db_state.get('technical_board_exists'):
        feedback.append("Board description incorrect.")

    # Criterion 3: Move Thread (35 pts)
    if db_state.get('message_moved'):
        score += 35
        feedback.append("Technical thread moved successfully.")
    else:
        feedback.append("Technical thread NOT moved to new board.")

    # Criterion 4: Lock Thread (30 pts)
    if db_state.get('message_locked'):
        score += 30
        feedback.append("Old thread locked successfully.")
    else:
        feedback.append("Old thread NOT locked.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }