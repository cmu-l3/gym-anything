#!/usr/bin/env python3
"""
Verifier for create_dunning_plan task.
Verifies that the dunning plan and its 3 levels were created correctly in the database.
"""

import json
import logging
import os
import tempfile
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_dunning_plan(traj, env_info, task_info):
    """
    Verify the dunning plan creation.
    
    Scoring Criteria:
    1. Dunning Header exists with correct name (15 pts)
    2. Header has 'Sequential' flag set (5 pts)
    3. Exactly 3 levels exist (10 pts)
    4. Level 1 details (30 days, 0 interval, 0 fee) (15 pts)
    5. Level 2 details (60 days, 30 interval, 25 fee) (20 pts)
    6. Level 3 details (90 days, 30 interval, 50 fee, 1.5% interest) (25 pts)
    7. Created during task session (Anti-gaming check) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # 1. Header Check
    if not result.get('plan_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dunning Plan 'Standard Collections' not found in database."
        }
    
    score += 15
    feedback_parts.append("Plan header found")

    # 2. Sequential Check
    is_seq = result.get('is_sequential', 'N')
    if is_seq == 'Y' or is_seq == True:
        score += 5
        feedback_parts.append("Sequential flag correct")
    else:
        feedback_parts.append(f"Sequential flag incorrect ({is_seq})")

    # 3. Level Count Check
    level_count = result.get('level_count', 0)
    if level_count == 3:
        score += 10
        feedback_parts.append("Level count correct (3)")
    else:
        feedback_parts.append(f"Level count incorrect (found {level_count}, expected 3)")

    # Parse levels
    levels = result.get('levels', [])
    
    # Helper to find level by days overdue
    def find_level(days):
        for lvl in levels:
            # Handle string/float conversions
            try:
                d = float(lvl.get('days_after', 0))
                if abs(d - days) < 0.1:
                    return lvl
            except:
                pass
        return None

    # 4. Check Level 1 (30 days)
    l1 = find_level(30)
    if l1:
        l1_score = 0
        if float(l1.get('days_between', -1)) == 0: l1_score += 5
        if float(l1.get('fee', -1)) == 0: l1_score += 5
        if float(l1.get('interest', -1)) == 0: l1_score += 5
        
        score += l1_score
        if l1_score == 15:
            feedback_parts.append("Level 1 correct")
        else:
            feedback_parts.append(f"Level 1 partial ({l1_score}/15)")
    else:
        feedback_parts.append("Level 1 (30 days) missing")

    # 5. Check Level 2 (60 days)
    l2 = find_level(60)
    if l2:
        l2_score = 0
        if float(l2.get('days_between', -1)) == 30: l2_score += 5
        if float(l2.get('fee', -1)) == 25: l2_score += 15 # Heavy weight on fee
        
        score += l2_score
        if l2_score == 20:
            feedback_parts.append("Level 2 correct")
        else:
            feedback_parts.append(f"Level 2 partial ({l2_score}/20)")
    else:
        feedback_parts.append("Level 2 (60 days) missing")

    # 6. Check Level 3 (90 days)
    l3 = find_level(90)
    if l3:
        l3_score = 0
        if float(l3.get('days_between', -1)) == 30: l3_score += 5
        if float(l3.get('fee', -1)) == 50: l3_score += 10
        if float(l3.get('interest', -1)) == 1.5: l3_score += 10
        
        score += l3_score
        if l3_score == 25:
            feedback_parts.append("Level 3 correct")
        else:
            feedback_parts.append(f"Level 3 partial ({l3_score}/25)")
    else:
        feedback_parts.append("Level 3 (90 days) missing")

    # 7. Anti-gaming (Created timestamp check)
    task_start = result.get('task_start_time', 0)
    created_time = result.get('plan_created_timestamp', 0)
    
    # Allow small clock skew (e.g. 60s) or if timestamp is 0 (parsing failed), usually give benefit of doubt if ID is new
    # But strictly, created should be > start
    if created_time > (task_start - 60):
        score += 10
        feedback_parts.append("Created during session")
    else:
        feedback_parts.append(f"Creation time suspicious (Created: {created_time}, Start: {task_start})")

    # Final result
    passed = score >= 85 # Strict pass threshold for config tasks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }