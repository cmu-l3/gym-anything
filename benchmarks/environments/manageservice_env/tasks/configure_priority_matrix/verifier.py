#!/usr/bin/env python3
"""
Verifier for configure_priority_matrix task.

Logic:
1. Load result JSON from container.
2. Compare 'final_matrix' against expected mapping defined in task metadata.
3. Verify that 'final_matrix' is different from 'initial_matrix' (anti-gaming).
4. Score based on correct cells.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_priority_matrix(traj, env_info, task_info):
    """
    Verifies the ServiceDesk Plus Priority Matrix configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    final_matrix = result.get("final_matrix", [])
    initial_matrix = result.get("initial_matrix", [])
    app_running = result.get("app_running", False)

    if not app_running:
        return {"passed": False, "score": 0, "feedback": "ServiceDesk Plus was not running at the end of the task."}

    if not final_matrix:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve Priority Matrix data from database."}

    # 2. Get Expected Configuration
    metadata = task_info.get("metadata", {})
    expected_mapping = metadata.get("expected_mapping", [])
    
    # If metadata missing, fallback to the standard requirements
    if not expected_mapping:
        expected_mapping = [
            {"impact": "High", "urgency": "High", "priority": "High"},
            {"impact": "High", "urgency": "Medium", "priority": "High"},
            {"impact": "High", "urgency": "Low", "priority": "Medium"},
            {"impact": "Medium", "urgency": "High", "priority": "High"},
            {"impact": "Medium", "urgency": "Medium", "priority": "Medium"},
            {"impact": "Medium", "urgency": "Low", "priority": "Low"},
            {"impact": "Low", "urgency": "High", "priority": "Medium"},
            {"impact": "Low", "urgency": "Medium", "priority": "Low"},
            {"impact": "Low", "urgency": "Low", "priority": "Low"}
        ]

    # 3. Scoring Logic
    score = 0
    max_score = 100
    feedback = []
    
    # Points breakdown: 
    # - 10 points base for having any data
    # - 10 points per correct cell (9 cells = 90 points)
    # Total = 100
    
    if len(final_matrix) > 0:
        score += 10
    
    correct_cells = 0
    total_cells_checked = 0
    
    # Normalize data for comparison (lowercase)
    def normalize_entry(entry):
        return {
            "impact": str(entry.get("impact", "")).lower(),
            "urgency": str(entry.get("urgency", "")).lower(),
            "priority": str(entry.get("priority", "")).lower()
        }

    final_lookup = {}
    for item in final_matrix:
        norm = normalize_entry(item)
        key = (norm['impact'], norm['urgency'])
        final_lookup[key] = norm['priority']

    for target in expected_mapping:
        norm_target = normalize_entry(target)
        key = (norm_target['impact'], norm_target['urgency'])
        expected_prio = norm_target['priority']
        
        total_cells_checked += 1
        
        if key in final_lookup:
            actual_prio = final_lookup[key]
            if actual_prio == expected_prio:
                score += 10
                correct_cells += 1
            else:
                feedback.append(f"Mismatch: {target['impact']}/{target['urgency']} -> Expected {target['priority']}, got {actual_prio.title()}")
        else:
            feedback.append(f"Missing mapping for {target['impact']}/{target['urgency']}")

    # 4. Anti-Gaming Check
    # Ensure the matrix actually changed from initial state
    # (Only strictly required if the initial state wasn't already the target state)
    
    # Simple JSON string comparison isn't robust due to ordering, so compare contents
    initial_lookup = {}
    for item in initial_matrix:
        norm = normalize_entry(item)
        key = (norm['impact'], norm['urgency'])
        initial_lookup[key] = norm['priority']
        
    changes_made = 0
    for key, val in final_lookup.items():
        if key in initial_lookup and initial_lookup[key] != val:
            changes_made += 1
            
    # If the target state IS the initial state (unlikely but possible), we accept it.
    # Otherwise, we expect at least 1 change or perfect score.
    if changes_made == 0 and score < 100:
        feedback.append("Warning: No changes detected from initial state.")
    
    # 5. Finalize
    score = min(score, 100)
    passed = (score >= 70) # Threshold allows for minor errors but requires key logic
    
    feedback_str = f"Score: {score}/100. Correct Cells: {correct_cells}/{total_cells_checked}. "
    if feedback:
        feedback_str += "Issues: " + "; ".join(feedback)
    else:
        feedback_str += "Perfect configuration."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }