#!/usr/bin/env python3
"""
Verifier for data_approval_workflow task.

Scoring (100 points total):
- Workflow exists (MANDATORY) (30 pts)
- Workflow has >= 2 approval levels (20 pts)
- Approval levels exist in system (net new levels check) (15 pts)
- Dataset has workflow assigned (25 pts)
- Workflow created after task start (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_data_approval_workflow(traj, env_info, task_info):
    """Verify Data Approval Workflow configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/data_approval_workflow_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Workflow exists (MANDATORY)
    workflow_found = result.get('workflow_found', False)
    workflow_name = result.get('workflow_name', 'Unknown')
    
    if not workflow_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Mandatory: No Data Approval Workflow found with name containing 'Health Data Review'.",
            "subscores": {}
        }
    
    score += 30
    subscores['workflow_exists'] = True
    feedback_parts.append(f"Workflow '{workflow_name}' found (+30)")

    # Criterion 2: Workflow Levels
    levels_count = result.get('workflow_levels_count', 0)
    if levels_count >= 2:
        score += 20
        subscores['levels_count'] = True
        feedback_parts.append(f"Workflow has {levels_count} levels (+20)")
    else:
        subscores['levels_count'] = False
        feedback_parts.append(f"Workflow has only {levels_count} levels (min 2 required)")

    # Criterion 3: Approval levels exist (checking for net new levels as proxy for creation)
    # This is a bit lenient, accepting if they created levels even if not perfectly linked, 
    # but the workflow_levels_count check ensures they are linked.
    net_new = result.get('net_new_levels', 0)
    if net_new >= 2:
        score += 15
        subscores['new_levels'] = True
        feedback_parts.append(f"New approval levels detected (+15)")
    elif levels_count >= 2:
        # If they linked existing levels (if available) or detection failed, 
        # but the workflow is valid, give partial credit or full if levels are valid.
        # We'll give credit here if the workflow logic is sound.
        score += 15
        subscores['new_levels'] = True
        feedback_parts.append(f"Approval levels validated via workflow (+15)")
    else:
        feedback_parts.append("Could not verify creation of new approval levels")

    # Criterion 4: Dataset Assignment
    dataset_assigned = result.get('dataset_assigned', False)
    ds_name = result.get('assigned_dataset_name', '')
    
    if dataset_assigned:
        score += 25
        subscores['dataset_assigned'] = True
        feedback_parts.append(f"Assigned to dataset '{ds_name}' (+25)")
    else:
        subscores['dataset_assigned'] = False
        feedback_parts.append("No dataset found with this workflow assigned")

    # Criterion 5: Creation Timestamp (Anti-gaming)
    created_after = result.get('workflow_created_after', False)
    if created_after:
        score += 10
        subscores['fresh_creation'] = True
        feedback_parts.append("Workflow created during task (+10)")
    else:
        feedback_parts.append("Workflow appears to be pre-existing or timestamp check failed")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }