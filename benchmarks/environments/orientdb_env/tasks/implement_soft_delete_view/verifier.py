#!/usr/bin/env python3
"""
Verifier for implement_soft_delete_view task.

Verification Logic:
1. Schema Check (20 pts): 'Reviews' class must have 'IsHidden' property of type BOOLEAN.
2. Data Tagging Check (40 pts): 
   - 1-star marker review must have IsHidden=true.
   - 5-star marker review must NOT have IsHidden=true.
3. View Logic Check (40 pts):
   - 'PublicReviews' view must return the 5-star marker.
   - 'PublicReviews' view must NOT return the 1-star marker.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_soft_delete_view(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Schema Check (20 pts) ---
    schema = result.get("schema_snapshot", {})
    classes = schema.get("classes", [])
    
    reviews_class = next((c for c in classes if c.get("name") == "Reviews"), None)
    is_hidden_prop = None
    
    if reviews_class:
        properties = reviews_class.get("properties", [])
        is_hidden_prop = next((p for p in properties if p.get("name") == "IsHidden"), None)
    
    if is_hidden_prop:
        prop_type = is_hidden_prop.get("type", "").upper()
        if prop_type == "BOOLEAN":
            score += 20
            feedback.append("[PASS] Property Reviews.IsHidden (BOOLEAN) created.")
        else:
            feedback.append(f"[FAIL] Property Reviews.IsHidden exists but type is {prop_type} (expected BOOLEAN).")
    else:
        feedback.append("[FAIL] Property Reviews.IsHidden not found.")


    # --- Criterion 2: Data Tagging Check (40 pts) ---
    # Check Toxic Marker (Stars=1) -> Expect IsHidden=true
    toxic_data = result.get("marker_toxic", {}).get("result", [])
    toxic_val = toxic_data[0].get("IsHidden") if toxic_data else None
    
    # Check Good Marker (Stars=5) -> Expect IsHidden=false or null
    good_data = result.get("marker_good", {}).get("result", [])
    good_val = good_data[0].get("IsHidden") if good_data else None

    tagging_pass = False
    if toxic_val is True:
        if good_val is not True: # Can be False or None
            score += 40
            tagging_pass = True
            feedback.append("[PASS] Low-star reviews hidden, high-star reviews visible.")
        else:
            score += 20
            feedback.append("[PARTIAL] Low-star reviews hidden, but high-star reviews also hidden.")
    else:
        feedback.append(f"[FAIL] Low-star reviews not tagged hidden (Value: {toxic_val}).")


    # --- Criterion 3: View Logic Check (40 pts) ---
    view_result = result.get("view_result", {})
    
    # If view creation failed, result usually contains 'error' or 'exception'
    if "exception" in view_result or "error" in view_result:
        feedback.append("[FAIL] View 'PublicReviews' query failed (likely does not exist).")
    else:
        rows = view_result.get("result", [])
        texts = [r.get("Text") for r in rows]
        
        has_good = "MARKER_GOOD_REVIEW" in texts
        has_toxic = "MARKER_TOXIC_REVIEW" in texts
        
        if has_good and not has_toxic:
            score += 40
            feedback.append("[PASS] View 'PublicReviews' correctly filters content.")
        elif not has_good:
            # Maybe view is empty or filtering everything?
            feedback.append("[FAIL] View 'PublicReviews' does not show safe content.")
        elif has_toxic:
            feedback.append("[FAIL] View 'PublicReviews' fails to hide toxic content.")

    # Final result
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }