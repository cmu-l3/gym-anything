#!/usr/bin/env python3
"""
Verifier for create_kanban_board task.

Verifies:
1. A board named "Design Workflow Board" exists in the E-Commerce project.
2. The board is a 'Status' (action) board.
3. The board has at least 2 columns (New, In Progress).
4. Anti-gaming: The board count increased from the start of the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_kanban_board(traj, env_info, task_info):
    """
    Verify the Kanban board creation task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_board_name', "Design Workflow Board")
    
    # 2. Retrieve result file
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

    # 3. Parse Data
    rails_data = result.get('rails_data', {})
    initial_count = result.get('initial_board_count', 0)
    
    if rails_data.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verifier Error: Rails query failed: {rails_data['error']}"
        }

    board_found = rails_data.get('board_found', False)
    board_data = rails_data.get('board_data', {}) or {}
    total_board_count = rails_data.get('total_board_count', 0)

    feedback_parts = []
    score = 0
    max_score = 100

    # --- CRITERION 1: Board Exists (35 pts) ---
    if board_found:
        score += 35
        feedback_parts.append(f"Board '{expected_name}' found")
    else:
        feedback_parts.append(f"Board '{expected_name}' NOT found")
        # If board not found, other checks will fail, but we check anti-gaming anyway
        if total_board_count > initial_count:
            feedback_parts.append(f"(However, {total_board_count - initial_count} new board(s) were created with different names)")

    # --- CRITERION 2: Board Type (20 pts) ---
    # Expected: type="action", attribute="status"
    if board_found:
        b_type = board_data.get('type_option')
        b_attr = board_data.get('attribute_option')
        
        if b_type == 'action' and b_attr == 'status':
            score += 20
            feedback_parts.append("Board type is correctly set to 'Status'")
        else:
            feedback_parts.append(f"Incorrect board type. Expected Status board, got type='{b_type}', attr='{b_attr}'")

    # --- CRITERION 3: Column Count (30 pts) ---
    # Expected: >= 2 columns
    if board_found:
        col_count = board_data.get('column_count', 0)
        if col_count >= 2:
            score += 30
            feedback_parts.append(f"Board has {col_count} columns (>= 2 required)")
        elif col_count == 1:
            score += 10 # Partial credit
            feedback_parts.append("Board has only 1 column (2 required for full points)")
        else:
            feedback_parts.append("Board has 0 columns (empty)")

    # --- CRITERION 4: Anti-Gaming / Created During Task (15 pts) ---
    if total_board_count > initial_count:
        score += 15
        feedback_parts.append(f"Board count increased ({initial_count} -> {total_board_count})")
    else:
        # If the board was found but count didn't increase, it means it pre-existed (gaming)
        if board_found:
            feedback_parts.append("FAIL: Board count did not increase. Verify you created a NEW board.")
        else:
            feedback_parts.append("Board count did not increase")

    # Final Evaluation
    # Threshold 55: Needs (Board Found 35) + (Anti-gaming 15) + (Partial Type/Columns 5)
    passed = score >= 55 and board_found and (total_board_count > initial_count)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }