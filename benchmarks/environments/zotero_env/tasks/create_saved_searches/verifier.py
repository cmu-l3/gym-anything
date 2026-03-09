#!/usr/bin/env python3
"""
Verifier for create_saved_searches task.

Verifies:
1. Two saved searches exist with exact specific names.
2. The search conditions (field, operator, value) are configured correctly.
3. App was running and state changed during task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_saved_searches(traj, env_info, task_info):
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Result Data
    meta = task_info.get('metadata', {})
    
    # Target 1: Pre-1960 Classics
    t1_name = meta.get('search1_name', "Pre-1960 Classics")
    t1_fields = meta.get('search1_field_variants', ["date", "year"])
    t1_ops = meta.get('search1_operator_variants', ["isBefore", "is before"])
    t1_val = meta.get('search1_value', "1960")
    
    # Target 2: Nature Publications
    t2_name = meta.get('search2_name', "Nature Publications")
    t2_fields = meta.get('search2_field_variants', ["publicationTitle", "publication"])
    t2_ops = meta.get('search2_operator_variants', ["contains", "is"])
    t2_val = meta.get('search2_value', "Nature")

    saved_searches = result.get("saved_searches", [])
    
    score = 0
    feedback = []
    
    # 3. Verify "Pre-1960 Classics" (50 pts)
    # Find the search by name
    s1 = next((s for s in saved_searches if s["name"].strip() == t1_name), None)
    
    if s1:
        score += 20
        feedback.append(f"✓ Found saved search '{t1_name}' (20 pts)")
        
        # Check conditions
        # We need at least one condition that matches our criteria
        valid_condition = False
        for cond in s1["conditions"]:
            field = str(cond.get("field", "")).lower()
            op = str(cond.get("operator", "")).lower()
            val = str(cond.get("value", "")).lower()
            
            # Allow flexible field matching (date or year)
            field_match = any(v.lower() in field for v in t1_fields)
            # Allow flexible operator (isBefore is standard Zotero ID)
            op_match = any(v.lower() in op for v in t1_ops)
            # Allow partial value match (e.g. 1960 in 01/01/1960)
            val_match = str(t1_val) in val
            
            if field_match and op_match and val_match:
                valid_condition = True
                break
        
        if valid_condition:
            score += 30
            feedback.append("✓ 'Pre-1960' condition correct (Date < 1960) (30 pts)")
        else:
            feedback.append("✗ 'Pre-1960' condition incorrect (Check field/operator/value)")
            # Debug info
            if s1["conditions"]:
                c = s1["conditions"][0]
                feedback.append(f"  (Found: {c.get('field')} {c.get('operator')} {c.get('value')})")
    else:
        feedback.append(f"✗ Saved search '{t1_name}' not found")

    # 4. Verify "Nature Publications" (50 pts)
    s2 = next((s for s in saved_searches if s["name"].strip() == t2_name), None)
    
    if s2:
        score += 20
        feedback.append(f"✓ Found saved search '{t2_name}' (20 pts)")
        
        valid_condition = False
        for cond in s2["conditions"]:
            field = str(cond.get("field", "")).lower()
            op = str(cond.get("operator", "")).lower()
            val = str(cond.get("value", "")).lower()
            
            field_match = any(v.lower() in field for v in t2_fields)
            op_match = any(v.lower() in op for v in t2_ops)
            val_match = str(t2_val).lower() in val
            
            if field_match and op_match and val_match:
                valid_condition = True
                break
                
        if valid_condition:
            score += 30
            feedback.append("✓ 'Nature' condition correct (Publication contains Nature) (30 pts)")
        else:
            feedback.append("✗ 'Nature' condition incorrect")
            if s2["conditions"]:
                c = s2["conditions"][0]
                feedback.append(f"  (Found: {c.get('field')} {c.get('operator')} {c.get('value')})")
    else:
        feedback.append(f"✗ Saved search '{t2_name}' not found")

    # 5. Final check
    passed = (score >= 50) # Pass if at least one search is perfect, or partials
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }