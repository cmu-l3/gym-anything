#!/usr/bin/env python3
"""
Verifier for assign_sprint_iteration task.

Logic:
1. Parse the SRS.json file from the project.
2. Identify all requirements with Priority = 'High'.
3. Verify these (and ONLY these) have Iteration = 'Sprint 1'.
4. Check anti-gaming (file modification time).
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_sprint_iteration(traj, env_info, task_info):
    """
    Verify that High priority requirements are assigned to Sprint 1.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_val = metadata.get('target_value', "Sprint 1")
    target_pri = metadata.get('target_priority', "High")
    
    # 1. Retrieve Task Result Metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Prerequisites
    if not task_result.get('file_modified_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project file was not saved/modified during the task."
        }

    srs_path = task_result.get('srs_file_path')
    if not srs_path:
        return {"passed": False, "score": 0, "feedback": "SRS file path not found in result."}

    # 3. Retrieve and Parse SRS.json
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve SRS.json: {e}"}
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    # 4. Analyze Data
    # Flatten the hierarchy to get all requirement objects
    all_requirements = []
    
    def extract_reqs(items):
        for item in items:
            # We consider an item a requirement if it has an ID and some text/heading
            if 'id' in item:
                all_requirements.append(item)
            if 'children' in item:
                extract_reqs(item['children'])
                
    extract_reqs(srs_data.get('data', []))

    # Metrics
    high_pri_total = 0
    high_pri_correct = 0
    other_pri_total = 0
    other_pri_correct = 0 # i.e., NOT changed to target_val

    # Helper to check priority match (handle case sensitivity)
    def is_priority(item, p_str):
        p = item.get('priority', '')
        return str(p).lower() == p_str.lower()

    for req in all_requirements:
        # Get attribute values
        iteration = req.get('iteration', '')
        
        if is_priority(req, target_pri):
            high_pri_total += 1
            if iteration == target_val:
                high_pri_correct += 1
        else:
            # Only count items that actually look like requirements (have priority set)
            # ignore sections that might not have priority
            if req.get('priority'): 
                other_pri_total += 1
                if iteration != target_val:
                    other_pri_correct += 1

    # 5. Calculate Score
    score = 0
    feedback = []

    # Recall: Did we capture all High priority items? (40 pts)
    if high_pri_total > 0:
        recall = high_pri_correct / high_pri_total
        score += int(recall * 40)
        feedback.append(f"Assigned {high_pri_correct}/{high_pri_total} High priority items.")
    else:
        feedback.append("No High priority items found in data (setup error?).")

    # Precision: Did we leave others alone? (30 pts)
    if other_pri_total > 0:
        precision = other_pri_correct / other_pri_total
        score += int(precision * 30)
        if other_pri_correct < other_pri_total:
            feedback.append(f"Incorrectly assigned {other_pri_total - other_pri_correct} non-High items.")
        else:
            feedback.append("Correctly ignored all non-High items.")
    else:
        score += 30 # Default if no other items exist
    
    # Value Accuracy: Was it exactly "Sprint 1"? (20 pts)
    # (Implicitly checked above, but adding points for general success)
    if high_pri_correct > 0:
        score += 20
    
    # Persistence check (10 pts)
    if task_result.get('file_modified_during_task'):
        score += 10
        feedback.append("Changes saved successfully.")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "high_priority_total": high_pri_total,
            "high_priority_correct": high_pri_correct,
            "other_priority_total": other_pri_total,
            "other_priority_correct": other_pri_correct
        }
    }