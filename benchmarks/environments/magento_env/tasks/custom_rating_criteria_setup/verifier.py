#!/usr/bin/env python3
"""Verifier for Custom Rating Criteria task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rating_setup(traj, env_info, task_info):
    """
    Verify creation of 'Fit Accuracy' and 'Material Quality' ratings.
    
    Scoring:
    - Fit Accuracy exists: 20 pts
    - Fit Accuracy active: 10 pts
    - Fit Accuracy assigned to Default Store (ID 1): 20 pts (Critical)
    - Material Quality exists: 20 pts
    - Material Quality active: 10 pts
    - Material Quality assigned to Default Store (ID 1): 20 pts (Critical)
    
    Total: 100 pts. Pass threshold: 70 pts.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/rating_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Check Fit Accuracy
    fit = result.get('fit_accuracy', {})
    fit_stores = str(fit.get('store_ids', '')).split(',')
    
    if fit.get('found'):
        score += 20
        feedback_parts.append("Fit Accuracy created")
        
        if str(fit.get('is_active')) == '1':
            score += 10
        else:
            feedback_parts.append("Fit Accuracy NOT active")
            
        # Check store assignment (ID 1 is Default Store View)
        if '1' in fit_stores:
            score += 20
        else:
            feedback_parts.append("Fit Accuracy NOT assigned to Default Store View (Frontend invisible)")
            
        # Optional check for sort order (not strictly weighted heavily in design but good for feedback)
        if str(fit.get('position')) == '10':
            feedback_parts.append("Fit Accuracy sort order correct")
    else:
        feedback_parts.append("Fit Accuracy NOT found")

    # Check Material Quality
    mat = result.get('material_quality', {})
    mat_stores = str(mat.get('store_ids', '')).split(',')
    
    if mat.get('found'):
        score += 20
        feedback_parts.append("Material Quality created")
        
        if str(mat.get('is_active')) == '1':
            score += 10
        else:
            feedback_parts.append("Material Quality NOT active")
            
        if '1' in mat_stores:
            score += 20
        else:
            feedback_parts.append("Material Quality NOT assigned to Default Store View (Frontend invisible)")
            
        if str(mat.get('position')) == '20':
            feedback_parts.append("Material Quality sort order correct")
    else:
        feedback_parts.append("Material Quality NOT found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }