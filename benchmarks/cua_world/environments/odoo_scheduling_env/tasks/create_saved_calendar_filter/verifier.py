#!/usr/bin/env python3
"""
Verifier for create_saved_calendar_filter task.

Criteria:
1. A saved filter named 'CFO Schedule' exists in ir.filters for calendar.event model.
2. The filter's domain correctly targets 'Grace Patel' (either by ID or string match).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_saved_calendar_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    score = 0
    feedback = []
    
    # Check for basic errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Database query error: {result['error']}"}

    # Criterion 1: Filter Existence (40 points)
    if result.get("filter_found"):
        score += 40
        feedback.append("Saved filter 'CFO Schedule' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No saved filter named 'CFO Schedule' found."}

    # Criterion 2: Domain Verification (60 points)
    # The domain should filter for Grace Patel.
    # Odoo domains for many2many (partner_ids) usually look like: [['partner_ids', 'in', [ID]]] or [['partner_ids', 'ilike', 'Name']]
    
    filter_details = result.get("filter_details", {})
    domain_str = str(filter_details.get("domain", ""))
    context_str = str(filter_details.get("context", ""))
    grace_id = result.get("grace_patel_id")
    
    target_found = False
    
    # Check 2a: ID-based match (Most robust)
    if grace_id and str(grace_id) in domain_str:
        target_found = True
        feedback.append(f"Filter correctly targets Grace Patel by ID ({grace_id}).")
        
    # Check 2b: Name-based match (Fallback)
    elif "Grace Patel" in domain_str or "Grace Patel" in context_str:
        target_found = True
        feedback.append("Filter targets Grace Patel by name.")
        
    if target_found:
        score += 60
    else:
        feedback.append(f"Filter domain '{domain_str}' does not appear to filter for Grace Patel.")
        score = max(score, 40) # Keep the 40 points for creating the filter object

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }