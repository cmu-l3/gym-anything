#!/usr/bin/env python3
"""
Verifier for configure_feature_team task in Azure DevOps.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_feature_team(traj, env_info, task_info):
    """
    Verify that the Platform team was configured correctly.
    
    Criteria:
    1. Team "Platform" exists (20 pts)
    2. Area Path "TailwindTraders\Platform" exists (10 pts)
    3. Iteration "Sprint 1" is active for Platform team (15 pts)
    4. Iteration "Sprint 2" is active for Platform team (15 pts)
    5. At least 3 items moved to Platform area path (25 pts)
    6. Specific expected items are among those moved (15 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_items = set(metadata.get('work_items_to_move', []))
    
    # Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. Check Team Existence
    if result.get('team_exists'):
        score += 20
        feedback.append("Team 'Platform' created.")
    else:
        feedback.append("Team 'Platform' NOT found.")
        
    # 2. Check Area Path
    if result.get('area_path_exists'):
        score += 10
        feedback.append("Area Path 'TailwindTraders\\Platform' created.")
    else:
        feedback.append("Area Path NOT found.")
        
    # 3 & 4. Check Iterations
    iterations = result.get('iterations', [])
    # Normalize comparison
    iterations_clean = [str(i).strip().lower() for i in iterations]
    
    if "sprint 1" in iterations_clean:
        score += 15
        feedback.append("Sprint 1 configured.")
    else:
        feedback.append("Sprint 1 missing from team iterations.")
        
    if "sprint 2" in iterations_clean:
        score += 15
        feedback.append("Sprint 2 configured.")
    else:
        feedback.append("Sprint 2 missing from team iterations.")
        
    # 5 & 6. Check Work Items
    moved_items = result.get('moved_items', [])
    # Allow partial matches on title since user might edit slightly, though script moves cleanly
    # Exact match preferred
    moved_set = set(moved_items)
    
    count_moved = len(moved_items)
    if count_moved >= 3:
        score += 25
        feedback.append(f"{count_moved} items moved to Platform area.")
    else:
        feedback.append(f"Only {count_moved} items moved (expected >= 3).")
        
    # Check specific titles
    # We check if expected items are in the moved list
    matches = 0
    for expected in expected_items:
        if expected in moved_set:
            matches += 1
            
    if matches >= 3:
        score += 15
        feedback.append("All target work items correctly reassigned.")
    elif matches > 0:
        partial_score = matches * 5
        score += partial_score
        feedback.append(f"{matches}/3 target work items reassigned.")
    else:
        feedback.append("None of the specific target items were reassigned.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }