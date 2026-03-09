#!/usr/bin/env python3
"""
Verifier for convert_misclassified_work_items task.

Criteria:
1. Item #1 (originally Bug) is now 'User Story' (30 pts)
2. Item #1 Description contains the original Repro Steps text (40 pts)
3. Item #2 (originally User Story) is now 'Task' (30 pts)

Anti-gaming:
- Checks specific IDs generated during setup (prevents creating new correct items and leaving old ones)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_misclassified_work_items(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: The agent runs on Windows, so paths are Windows-style, but copy_from_env handles it.
    # We try both forward/backward slashes to be safe with the interface.
    result_path_win = r"C:\Users\Docker\task_results\task_result.json"
    result_path_posix = "C:/Users/Docker/task_results/task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        try:
            copy_from_env(result_path_win, temp_file.name)
        except Exception:
            copy_from_env(result_path_posix, temp_file.name)
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get required text from metadata
    metadata = task_info.get('metadata', {})
    required_text_fragment = "Add wish list button" # Key part of "Requirement: Add wish list button..."

    score = 0
    feedback_parts = []
    
    # 1. Verify Item 1 Conversion (Bug -> User Story)
    type_1 = result.get('item_101_type', 'Unknown')
    if type_1 == 'User Story':
        score += 30
        feedback_parts.append("Item 'Shopping Cart Redesign' correctly converted to User Story.")
    else:
        feedback_parts.append(f"Item 'Shopping Cart Redesign' has incorrect type: {type_1} (Expected: User Story).")

    # 2. Verify Item 1 Content Preservation
    desc_1 = result.get('item_101_desc', '')
    if desc_1 and required_text_fragment.lower() in desc_1.lower():
        score += 40
        feedback_parts.append("Original Repro Steps preserved in Description.")
    else:
        feedback_parts.append("FAILED to preserve 'Repro Steps' text in the new Description.")

    # 3. Verify Item 2 Conversion (User Story -> Task)
    type_2 = result.get('item_102_type', 'Unknown')
    if type_2 == 'Task':
        score += 30
        feedback_parts.append("Item 'Update API Schema' correctly converted to Task.")
    else:
        feedback_parts.append(f"Item 'Update API Schema' has incorrect type: {type_2} (Expected: Task).")

    # VLM Check (Secondary) - Just verifying screenshot exists for evidence
    screenshot_path = result.get('screenshot_path', '')
    if not screenshot_path:
         feedback_parts.append("(Warning: No screenshot verification available)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }