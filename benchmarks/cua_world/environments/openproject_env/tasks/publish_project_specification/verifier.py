#!/usr/bin/env python3
"""
Verifier for publish_project_specification task.
Checks if the Documents module was enabled, a global category created,
and a specific document uploaded with attachment.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_publish_project_specification(traj, env_info, task_info):
    """
    Verifies the publish_project_specification task.
    
    Criteria:
    1. Documents module enabled for project (20 pts)
    2. 'Specifications' category created (25 pts)
    3. Document 'Mobile App Specification v1' created (25 pts)
    4. Document assigned to 'Specifications' category (10 pts)
    5. File 'mobile_spec_v1.txt' attached (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    module_enabled = result.get('module_enabled', False)
    category_exists = result.get('category_exists', False)
    document_exists = result.get('document_exists', False)
    category_correct = result.get('category_correct', False)
    file_attached = result.get('file_attached', False)
    
    # Anti-gaming: Check timestamps
    task_start = result.get('task_start_time', 0)
    doc_created = result.get('doc_created_at', 0)
    cat_created = result.get('cat_created_at', 0)
    
    # Verify items were created *during* the task
    # We allow a small buffer or just check > start_time
    is_fresh_doc = document_exists and (doc_created >= task_start)
    is_fresh_cat = category_exists and (cat_created >= task_start)

    score = 0
    feedback_parts = []

    # Criterion 1: Module Enabled (20 pts)
    if module_enabled:
        score += 20
        feedback_parts.append("Module enabled")
    else:
        feedback_parts.append("Documents module NOT enabled")

    # Criterion 2: Category Exists (25 pts)
    if category_exists:
        if is_fresh_cat:
            score += 25
            feedback_parts.append("Category 'Specifications' created")
        else:
            # If it existed before (shouldn't happen due to setup), 0 points for creation
            feedback_parts.append("Category existed before task (anti-gaming fail)")
    else:
        feedback_parts.append("Category 'Specifications' NOT found")

    # Criterion 3: Document Created (25 pts)
    if document_exists:
        if is_fresh_doc:
            score += 25
            feedback_parts.append("Document entry created")
        else:
            feedback_parts.append("Document existed before task")
    else:
        feedback_parts.append("Document 'Mobile App Specification v1' NOT found")

    # Criterion 4: Category Assignment (10 pts)
    if category_correct:
        score += 10
        feedback_parts.append("Category assigned correctly")
    elif document_exists and category_exists:
        feedback_parts.append("Document has wrong category")

    # Criterion 5: File Attached (20 pts)
    if file_attached:
        score += 20
        feedback_parts.append("File attached")
    elif document_exists:
        feedback_parts.append("File 'mobile_spec_v1.txt' NOT attached")

    # Final logic
    passed = (score >= 80) and module_enabled and category_exists and document_exists and file_attached
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }