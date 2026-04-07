#!/usr/bin/env python3
"""
Verifier for structure_req_hierarchy task.

Verifies that the agent has restructured the flat requirement list into
a specific parent-child hierarchy in ReqView.

Criteria:
1. Document JSON exists and was modified.
2. ID Preservation: Original IDs (1-6) must exist (no delete/re-create).
3. Hierarchy Structure:
   - IMP-1 (ID 1) is parent of 2, 3, 4.
   - IMP-5 (ID 5) is parent of 6.
   - IMP-1 and IMP-5 are at root level.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DOC_PATH = "/home/ga/Documents/ReqView/structure_req_project/documents/IMP.json"

def find_node_by_id(nodes, target_id):
    """Recursively find a node dict by its 'id' field."""
    for node in nodes:
        if str(node.get('id')) == str(target_id):
            return node
        if 'children' in node:
            found = find_node_by_id(node['children'], target_id)
            if found:
                return found
    return None

def get_node_level_and_parent(nodes, target_id, current_level=1, parent_id=None):
    """
    Recursively find node and return (level, parent_id).
    Returns (None, None) if not found.
    """
    for node in nodes:
        if str(node.get('id')) == str(target_id):
            return current_level, parent_id
        
        if 'children' in node:
            level, pid = get_node_level_and_parent(
                node['children'], 
                target_id, 
                current_level + 1, 
                node.get('id')
            )
            if level is not None:
                return level, pid
    return None, None

def verify_structure_req_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the document JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(DOC_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            doc_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse document file: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    root_nodes = doc_data.get('data', [])
    score = 0
    feedback = []
    
    # Define expected relationships: Child ID -> Parent ID
    # Parent ID 'None' means root level
    expected_parents = {
        '1': None,
        '2': '1',
        '3': '1',
        '4': '1',
        '5': None,
        '6': '5'
    }

    # 3. Verification Loop
    missing_ids = []
    wrong_parents = []
    correct_count = 0

    for child_id, expected_parent_id in expected_parents.items():
        # Check if node exists
        node = find_node_by_id(root_nodes, child_id)
        if not node:
            missing_ids.append(f"IMP-{child_id}")
            continue

        # Check hierarchy
        level, actual_parent_id = get_node_level_and_parent(root_nodes, child_id)
        
        # Normalize IDs to strings for comparison
        actual_pid_str = str(actual_parent_id) if actual_parent_id is not None else "root"
        expected_pid_str = str(expected_parent_id) if expected_parent_id is not None else "root"

        if actual_pid_str == expected_pid_str:
            correct_count += 1
        else:
            wrong_parents.append(f"IMP-{child_id} is under {actual_pid_str} (expected {expected_pid_str})")

    # 4. Scoring
    # Max score 100.
    # 6 items to check. Each worth ~16.6 points.
    
    item_score = 0
    if len(expected_parents) > 0:
        item_score = (correct_count / len(expected_parents)) * 100

    score = int(item_score)

    # Penalize for missing IDs (indicates deletion/recreation gaming)
    if missing_ids:
        feedback.append(f"FAILED: IDs missing (re-created?): {', '.join(missing_ids)}")
        score = 0 # Zero score if original IDs are lost
    elif correct_count == len(expected_parents):
        feedback.append("SUCCESS: All requirements strictly hierarchical as requested.")
    else:
        feedback.append(f"Structure errors: {'; '.join(wrong_parents)}")

    # 5. Result
    return {
        "passed": score >= 90,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "correct_nodes": correct_count,
            "total_nodes": len(expected_parents),
            "errors": wrong_parents
        }
    }