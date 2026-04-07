#!/usr/bin/env python3
"""
Verifier for create_project_forums task.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_forums(traj, env_info, task_info):
    """
    Verify that the agent created the specific forums, topics, and replies.
    
    Criteria:
    1. Forum 'Renovation Planning' exists (15 pts)
    2. Forum 'Logistics & Scheduling' exists (15 pts)
    3. Forum descriptions match keywords (10 pts)
    4. Topic 'Floor Plan Review' exists in Renovation forum (12 pts)
    5. Topic 'IT Equipment' exists in Logistics forum (12 pts)
    6. Topic bodies contain required text (11 pts)
    7. Reply exists on Floor Plan topic with required text (15 pts)
    8. Anti-gaming: All timestamps > task start time (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    task_start = result_data.get('task_start_time', 0)
    redmine_data = result_data.get('redmine_data', {})
    
    if redmine_data.get('error'):
        return {"passed": False, "score": 0, "feedback": f"DB Query Error: {redmine_data['error']}"}

    boards = redmine_data.get('boards', [])
    messages = redmine_data.get('messages', [])
    
    score = 0
    feedback = []
    
    # --- Check Forums (Boards) ---
    
    # 1. Renovation Planning
    reno_board = next((b for b in boards if "renovation planning" in b['name'].lower()), None)
    if reno_board:
        score += 15
        feedback.append("Forum 'Renovation Planning' created.")
    else:
        feedback.append("FAIL: Forum 'Renovation Planning' not found.")
        
    # 2. Logistics & Scheduling
    logi_board = next((b for b in boards if "logistics" in b['name'].lower()), None)
    if logi_board:
        score += 15
        feedback.append("Forum 'Logistics & Scheduling' created.")
    else:
        feedback.append("FAIL: Forum 'Logistics & Scheduling' not found.")

    # 3. Descriptions
    desc_score = 0
    if reno_board and ("renovation design" in reno_board['description'].lower() or "planning decision" in reno_board['description'].lower()):
        desc_score += 5
    if logi_board and ("timeline" in logi_board['description'].lower() or "scheduling" in logi_board['description'].lower()):
        desc_score += 5
    
    if desc_score > 0:
        score += desc_score
        feedback.append(f"Forum descriptions partially/fully correct (+{desc_score}).")
    else:
        feedback.append("Forum descriptions missing or incorrect.")

    # --- Check Topics ---
    
    # 4. Floor Plan Topic
    # Should be in Reno board, but we'll accept it in any board with penalty if strict, but loose here
    floor_topic = next((m for m in messages if m['parent_id'] is None and "floor plan" in m['subject'].lower()), None)
    if floor_topic:
        if reno_board and floor_topic['board_id'] == reno_board['id']:
            score += 12
            feedback.append("Topic 'Floor Plan Review' created in correct forum.")
        else:
            score += 6
            feedback.append("Topic 'Floor Plan Review' created but in WRONG forum.")
    else:
        feedback.append("FAIL: Topic 'Floor Plan Review' not found.")

    # 5. IT Equipment Topic
    it_topic = next((m for m in messages if m['parent_id'] is None and "it equipment" in m['subject'].lower()), None)
    if it_topic:
        if logi_board and it_topic['board_id'] == logi_board['id']:
            score += 12
            feedback.append("Topic 'IT Equipment Schedule' created in correct forum.")
        else:
            score += 6
            feedback.append("Topic 'IT Equipment Schedule' created but in WRONG forum.")
    else:
        feedback.append("FAIL: Topic 'IT Equipment Schedule' not found.")

    # 6. Topic Bodies
    body_score = 0
    if floor_topic and ("open office" in floor_topic['content'].lower() or "meeting room" in floor_topic['content'].lower()):
        body_score += 6
    if it_topic and ("relocating" in it_topic['content'].lower() or "march 15" in it_topic['content'].lower()):
        body_score += 5
    
    if body_score > 0:
        score += body_score
        feedback.append(f"Topic content valid (+{body_score}).")

    # 7. Reply
    # Look for a message that has parent_id = floor_topic['id']
    reply_found = False
    if floor_topic:
        reply = next((m for m in messages if m['parent_id'] == floor_topic['id']), None)
        if reply:
            if "quiet workspace" in reply['content'].lower() or "east window" in reply['content'].lower():
                score += 15
                reply_found = True
                feedback.append("Reply posted with correct content.")
            else:
                score += 5
                reply_found = True
                feedback.append("Reply posted but content mismatch.")
    
    if not reply_found:
        feedback.append("FAIL: No reply found on 'Floor Plan Review' topic.")

    # 8. Anti-gaming (Timestamps)
    # Check if all identified items were created after task_start
    items_to_check = [reno_board, logi_board, floor_topic, it_topic]
    # Filter out Nones
    items_to_check = [x for x in items_to_check if x is not None]
    
    timestamps_valid = True
    if not items_to_check:
        timestamps_valid = False # Nothing created
    else:
        for item in items_to_check:
            if item.get('created_on', 0) < task_start:
                timestamps_valid = False
                feedback.append(f"Anti-gaming: Item '{item.get('name') or item.get('subject')}' predates task start.")
    
    if timestamps_valid and len(items_to_check) > 0:
        score += 10
        feedback.append("Anti-gaming check passed (all new content).")
    else:
        # If we failed simply because nothing was created, we don't deduct (score is just 0)
        # But if things WERE created but old, we lose these 10 points
        pass

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }