#!/usr/bin/env python3
"""
Verifier for procure_quote_to_order task.
Checks:
1. Purchase Quotes module is enabled.
2. Correct Purchase Quote exists.
3. Correct Purchase Order exists.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_procure_quote_to_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    score = 0
    feedback = []

    # 1. Module Enabled (20 pts)
    if result.get("purchase_quotes_enabled"):
        score += 20
        feedback.append("Purchase Quotes module enabled.")
    else:
        feedback.append("Purchase Quotes module NOT enabled.")

    # 2. Quote Created (30 pts)
    q_det = result.get("quote_details", {})
    if result.get("quote_found"):
        q_score = 0
        if q_det.get("supplier") == "Exotic Liquids": q_score += 10
        if q_det.get("item") == "Chai": q_score += 10
        if q_det.get("has_100") and q_det.get("has_15"): q_score += 10
        
        score += q_score
        if q_score == 30:
            feedback.append("Purchase Quote created correctly.")
        else:
            feedback.append(f"Purchase Quote found but details mismatch (Score: {q_score}/30).")
    else:
        feedback.append("Purchase Quote NOT found.")

    # 3. Order Created (30 pts)
    o_det = result.get("order_details", {})
    if result.get("order_found"):
        o_score = 0
        if o_det.get("supplier") == "Exotic Liquids": o_score += 10
        if o_det.get("item") == "Chai": o_score += 10
        if o_det.get("has_100") and o_det.get("has_15"): o_score += 10
        
        score += o_score
        if o_score == 30:
            feedback.append("Purchase Order created correctly.")
        else:
            feedback.append(f"Purchase Order found but details mismatch (Score: {o_score}/30).")
    else:
        feedback.append("Purchase Order NOT found.")

    # 4. Workflow Continuity (20 pts)
    # If both are perfect, assume workflow is good (hard to programmatically detect "Copy to" click without VLM, 
    # but exact data match implies success).
    if score >= 80:
        score += 20
        feedback.append("Workflow completed successfully.")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }