#!/usr/bin/env python3
"""
Verifier for dataset_funding_attribute_config task.

Scoring (100 points):
- Category & Options Created: 20 pts
- Category Combo is Attribute (CRITICAL): 25 pts
- Dataset Configured: 20 pts
- Data Entry Successful: 35 pts

Pass threshold: 60 points
"""

import json
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_dataset_funding_attribute_config(traj, env_info, task_info):
    """
    Verifies that the agent configured the funding attribute correctly 
    and entered data using it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result file
    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    feedback = []

    # 1. Metadata Existence (20 pts)
    if result.get("cat_options_found") and result.get("cat_found"):
        score += 20
        feedback.append("Metadata (Options/Category) created successfully.")
    else:
        feedback.append("Failed to create required Category or Options.")

    # 2. Category Combo Attribute Type (25 pts)
    if result.get("cat_combo_found"):
        if result.get("is_attribute"):
            score += 25
            feedback.append("Category Combo created correctly as 'Attribute'.")
        else:
            feedback.append("CRITICAL: Category Combo created but NOT set to 'Attribute' type (Disaggregation vs Attribute error).")
    else:
        feedback.append("Category Combination 'Funding Source 2025' not found.")

    # 3. Dataset Configuration (20 pts)
    if result.get("dataset_correct"):
        score += 20
        feedback.append("Dataset 'Reproductive Health' successfully assigned to new Category Combo.")
    else:
        feedback.append("Dataset 'Reproductive Health' is not using the new Category Combo.")

    # 4. Data Entry (35 pts)
    if result.get("data_value_found"):
        score += 35
        feedback.append("Data value successfully entered using the new attribute!")
    else:
        feedback.append("No data found for Bo Hospital/Jan 2025 using the new funding attribute.")

    # Pass/Fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }