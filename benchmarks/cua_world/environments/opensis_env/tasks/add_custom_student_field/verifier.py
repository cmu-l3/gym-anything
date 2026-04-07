#!/usr/bin/env python3
"""
Verifier for add_custom_student_field task.

Verifies:
1. "Transportation" category creation.
2. "Bus Route Number" field creation.
3. Proper linking (Field belongs to Category).
4. Correct data type (Text).
5. Anti-gaming (Counts increased).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_custom_student_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_category = metadata.get('expected_category', 'Transportation')
    expected_field = metadata.get('expected_field', 'Bus Route Number')
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    categories = result.get('categories', [])
    fields = result.get('fields', [])
    counts = result.get('counts', {})

    # 1. Verify Category Exists (30 pts)
    target_category = None
    for cat in categories:
        # Case insensitive match
        if expected_category.lower() in cat.get('title', '').lower():
            target_category = cat
            break
            
    if target_category:
        score += 30
        feedback.append(f"Category '{expected_category}' created.")
    else:
        feedback.append(f"Category '{expected_category}' NOT found.")

    # 2. Verify Field Exists (30 pts)
    target_field = None
    for f in fields:
        if expected_field.lower() in f.get('title', '').lower():
            target_field = f
            break
            
    if target_field:
        score += 30
        feedback.append(f"Field '{expected_field}' created.")
    else:
        feedback.append(f"Field '{expected_field}' NOT found.")

    # 3. Verify Hierarchy (Field is in Category) (20 pts)
    if target_category and target_field:
        # Assuming database schema uses 'id' for category and 'category_id' in field table
        # We need to handle flexible schema keys just in case, but standard SQL export keys usually match columns
        cat_id = str(target_category.get('id', 'cat_missing'))
        field_cat_id = str(target_field.get('category_id', 'field_missing'))
        
        if cat_id == field_cat_id:
            score += 20
            feedback.append("Field correctly assigned to category.")
        else:
            feedback.append(f"Hierarchy mismatch: Field is in category {field_cat_id}, expected {cat_id}.")
    elif target_field:
        feedback.append("Cannot verify hierarchy because category was not found.")

    # 4. Verify Data Type (10 pts)
    # OpenSIS types: 0=Text, 1=Text Area, 2=Select, etc. (This varies by version)
    # Or types might be strings like 'text', 'textarea'
    if target_field:
        ftype = str(target_field.get('type', '')).lower()
        # Accepting common text indicators
        if ftype in ['0', 'text', 'string', 'textfield', 'text box']:
            score += 10
            feedback.append("Field type is correct (Text).")
        else:
            feedback.append(f"Field type '{ftype}' might be incorrect (expected Text).")

    # 5. Anti-Gaming / Clean Execution (10 pts)
    # Check if counts increased by exactly 1 (or at least increased)
    # This prevents finding pre-existing data if we were running on a dirty DB
    # For this specific task, we want to ensure *we* created it.
    initial_cat = counts.get('initial_cat', 0)
    final_cat = counts.get('final_cat', 0)
    initial_field = counts.get('initial_field', 0)
    final_field = counts.get('final_field', 0)

    if final_cat > initial_cat and final_field > initial_field:
        score += 10
        feedback.append("New records confirmed created during task.")
    else:
        feedback.append("Warning: Record counts did not increase as expected (Anti-gaming check).")

    # Pass Threshold
    passed = (score >= 80) and (target_category is not None) and (target_field is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }