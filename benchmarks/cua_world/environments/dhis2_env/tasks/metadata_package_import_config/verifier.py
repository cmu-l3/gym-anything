#!/usr/bin/env python3
"""
Verifier for Metadata Package Import Task.

Scoring (100 points total):
1. Data Elements Imported (30 pts):
   - Checks if DEs with specific UIDs exist (Anti-gaming: requires import or precise ID matching).
2. Dataset Created (20 pts):
   - Checks if a dataset named 'Community Health...' exists.
3. Dataset Configuration (10 pts):
   - Checks if Period Type is 'Monthly'.
4. Data Elements Linked (30 pts):
   - Checks if the 3 imported DEs are assigned to the Dataset.
5. Org Unit Assigned (10 pts):
   - Checks if the Dataset is assigned to at least one Organisation Unit.

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_metadata_package_import_config(traj, env_info, task_info):
    """Verify that metadata was imported and dataset configured correctly."""
    
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Data Elements (30 pts)
    # The agent receives 30 pts if all 3 DEs are found with the correct UIDs.
    de_count = result.get('data_elements_found_count', 0)
    if de_count == 3:
        score += 30
        feedback_parts.append("All 3 Data Elements imported successfully (+30)")
    elif de_count > 0:
        partial = de_count * 10
        score += partial
        feedback_parts.append(f"Imported {de_count}/3 Data Elements (+{partial})")
    else:
        feedback_parts.append("No Data Elements found with expected UIDs. Did you use the import app?")

    # 3. Check Dataset Existence (20 pts)
    ds_check = result.get('dataset_check', {})
    if ds_check.get('found'):
        score += 20
        feedback_parts.append(f"Dataset '{ds_check.get('name')}' created (+20)")
        
        # 4. Check Period Type (10 pts)
        period_type = ds_check.get('periodType', '')
        if period_type == 'Monthly':
            score += 10
            feedback_parts.append("Correct Monthly period type (+10)")
        else:
            feedback_parts.append(f"Incorrect period type: '{period_type}' (expected Monthly)")
            
        # 5. Check Links to Data Elements (30 pts)
        linked_count = ds_check.get('linked_de_count', 0)
        if linked_count == 3:
            score += 30
            feedback_parts.append("All Data Elements assigned to dataset (+30)")
        elif linked_count > 0:
            partial = linked_count * 10
            score += partial
            feedback_parts.append(f"{linked_count}/3 Data Elements assigned to dataset (+{partial})")
        else:
            feedback_parts.append("No Data Elements assigned to dataset")
            
        # 6. Check Org Unit Assignment (10 pts)
        assigned_count = ds_check.get('assigned_ou_count', 0)
        if assigned_count > 0:
            score += 10
            feedback_parts.append("Dataset assigned to Org Unit (+10)")
        else:
            feedback_parts.append("Dataset NOT assigned to any Org Unit")
            
    else:
        feedback_parts.append("Community Health Dataset not found")

    # 7. Final Assessment
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }