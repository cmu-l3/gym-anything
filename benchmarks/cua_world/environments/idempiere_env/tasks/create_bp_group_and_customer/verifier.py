#!/usr/bin/env python3
"""
Verifier for create_bp_group_and_customer task in iDempiere.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bp_group_and_customer(traj, env_info, task_info):
    """
    Verifies that:
    1. A BP Group 'Botanical Gardens' exists and was created during the task.
    2. A Business Partner 'City Botanical Garden' exists and was created during the task.
    3. The Business Partner is assigned to the 'Botanical Gardens' group.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result from container: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    task_start = result.get('task_start', 0)
    group_data = result.get('group_data')
    bp_data = result.get('bp_data')
    
    # 2. Verify BP Group (40 points max)
    if group_data:
        # Check creation time (anti-gaming)
        created_ts = float(group_data.get('created_ts', 0))
        if created_ts > task_start:
            score += 30
            feedback.append("Success: BP Group 'Botanical Gardens' created.")
            
            # Check search key
            if group_data.get('search_key') == 'BotGarden':
                score += 10
                feedback.append("Success: Group Search Key is 'BotGarden'.")
            else:
                feedback.append(f"Notice: Group Search Key is '{group_data.get('search_key')}', expected 'BotGarden'.")
        else:
            feedback.append("Fail: BP Group 'Botanical Gardens' existed before task started.")
    else:
        feedback.append("Fail: BP Group 'Botanical Gardens' not found.")
        
    # 3. Verify Business Partner and Linkage (60 points max)
    if bp_data:
        # Check creation time (anti-gaming)
        created_ts = float(bp_data.get('created_ts', 0))
        if created_ts > task_start:
            score += 30
            feedback.append("Success: Business Partner 'City Botanical Garden' created.")
            
            # Check Linkage
            if group_data and bp_data.get('c_bp_group_id') == group_data.get('c_bp_group_id'):
                score += 30
                feedback.append("Success: Business Partner is correctly linked to the new Group.")
            else:
                feedback.append("Fail: Business Partner is NOT linked to the 'Botanical Gardens' group.")
        else:
            feedback.append("Fail: Business Partner existed before task started.")
    else:
        feedback.append("Fail: Business Partner 'City Botanical Garden' not found.")
        
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }