#!/usr/bin/env python3
"""
Verifier for refactor_document_categories task.

Criteria:
1. 'Technical documentation' category must be DELETED (20 pts)
2. 'User documentation' must be renamed to 'User Manuals' (10 pts)
3. 'Test Plans' and 'Audit Reports' categories must be CREATED (10 pts each)
4. 'Legacy System Spec' document must NOT be deleted (25 pts)
5. 'Legacy System Spec' document must be moved to 'Test Plans' (25 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_document_categories(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    score = 0
    feedback_parts = []
    failed = False

    # Criterion 1: Deprecated category deleted (20 pts)
    if not db_state.get('tech_doc_exists', True):
        score += 20
        feedback_parts.append("Deleted 'Technical documentation'")
    else:
        feedback_parts.append("Failed to delete 'Technical documentation'")

    # Criterion 2: Renamed correctly (10 pts)
    if db_state.get('user_manuals_exists', False):
        score += 10
        feedback_parts.append("Renamed to 'User Manuals'")
    else:
        feedback_parts.append("'User Manuals' category not found")

    # Criterion 3: New categories created (20 pts total)
    if db_state.get('test_plans_exists', False):
        score += 10
        feedback_parts.append("Created 'Test Plans'")
    else:
        feedback_parts.append("'Test Plans' category not found")

    if db_state.get('audit_reports_exists', False):
        score += 10
        feedback_parts.append("Created 'Audit Reports'")
    else:
        feedback_parts.append("'Audit Reports' category not found")

    # Criterion 4: Document Preserved (25 pts)
    if db_state.get('doc_exists', False):
        score += 25
        feedback_parts.append("Document preserved")
        
        # Criterion 5: Document Reassigned (25 pts)
        doc_category = db_state.get('doc_category', '')
        if doc_category == 'Test Plans':
            score += 25
            feedback_parts.append("Document correctly reassigned to 'Test Plans'")
        else:
            feedback_parts.append(f"Document in wrong category: '{doc_category}' (expected 'Test Plans')")
    else:
        feedback_parts.append("CRITICAL: 'Legacy System Spec' document was deleted!")
        failed = True

    # Final Pass Logic
    # Pass threshold is 75, which means they MUST preserve the doc and get most categories right
    passed = (score >= 75) and not failed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }