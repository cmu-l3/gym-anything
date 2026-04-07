#!/usr/bin/env python3
"""
Verifier for post_demo_sales_workflow task.
Checks parent opportunity updates and child activity creations independently.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_demo_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stage = metadata.get('expected_stage', 'Proposal/Price Quote')
    expected_probability = str(metadata.get('expected_probability', 65))
    
    # Read result payload
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

    task_start = int(result.get('task_start', 0))
    feedback_parts = []
    score = 0
    
    opp = result.get('opportunity', {})
    meeting = result.get('meeting', {})
    task = result.get('task', {})

    # ==========================================
    # 1. Verify Opportunity Update (30 points)
    # ==========================================
    if opp.get('found', False):
        opp_mod_time = int(opp.get('modified_time', 0) or 0)
        
        # Check Stage (20 points)
        if opp.get('sales_stage') == expected_stage:
            score += 20
            feedback_parts.append("Opportunity stage updated correctly")
        else:
            feedback_parts.append(f"Opportunity stage incorrect (Got {opp.get('sales_stage')})")
            
        # Check Probability (10 points)
        # Account for possible floats like '65.000' from DB
        prob_val = opp.get('probability', '').split('.')[0]
        if prob_val == expected_probability:
            score += 10
            feedback_parts.append("Opportunity probability updated correctly")
            
        # Anti-gaming: Ensure it was actually modified during task
        if opp_mod_time < task_start:
            feedback_parts.append("WARNING: Opportunity was not modified during the task execution window")
            score -= 10 # Penalize if untouched
    else:
        feedback_parts.append("Opportunity not found")

    # ==========================================
    # 2. Verify Meeting Creation (35 points)
    # ==========================================
    if meeting.get('found', False):
        m_created = int(meeting.get('created_time', 0) or 0)
        
        # Check type (10 points)
        if meeting.get('type') in ['Meeting', 'Call', 'Events']:
            score += 10
            
        # Check status (15 points)
        if meeting.get('status') == metadata.get('meeting_status', 'Held'):
            score += 15
            feedback_parts.append("Meeting logged successfully and set to Held")
        else:
            feedback_parts.append(f"Meeting found but incorrect status ({meeting.get('status')})")
            
        # Anti-gaming check (10 points)
        if m_created >= task_start:
            score += 10
        else:
            feedback_parts.append("WARNING: Meeting record predates task start time")
    else:
        feedback_parts.append("Meeting activity missing or not linked to Opportunity")

    # ==========================================
    # 3. Verify Task Creation (35 points)
    # ==========================================
    if task.get('found', False):
        t_created = int(task.get('created_time', 0) or 0)
        
        # Check type (5 points)
        if task.get('type') == metadata.get('task_type', 'Task'):
            score += 5
            
        # Check Status (10 points)
        if task.get('status') == metadata.get('task_status', 'Not Started'):
            score += 10
            
        # Check Priority (10 points)
        if task.get('priority') == metadata.get('task_priority', 'High'):
            score += 10
            feedback_parts.append("Follow-up task scheduled correctly")
            
        # Anti-gaming check (10 points)
        if t_created >= task_start:
            score += 10
        else:
            feedback_parts.append("WARNING: Task record predates task start time")
    else:
        feedback_parts.append("Task activity missing or not linked to Opportunity")

    # ==========================================
    # Final Result Determination
    # ==========================================
    # Threshold is 70 to pass - guarantees at least opp update + one linked activity
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }