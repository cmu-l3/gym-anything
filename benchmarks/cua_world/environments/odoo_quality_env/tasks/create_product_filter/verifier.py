#!/usr/bin/env python3
"""
Verifier for create_product_filter task.

Criteria:
1. Filter record exists in ir.filters (40 pts)
2. Filter name is exactly "Chairs Only" (30 pts)
3. Filter domain correctly targets "Office Chair" (30 pts)
   - Accepts domain containing product ID
   - Accepts domain containing product Name (ilike)
"""

import json
import os
import logging
import tempfile
import ast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_product_filter(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get("expected_filter_name", "Chairs Only")
    
    # 2. Retrieve Result JSON
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

    # 3. Evaluate
    score = 0
    feedback_parts = []
    
    # Check 1: Filter Exists (40 pts)
    if result.get("filter_found"):
        score += 40
        feedback_parts.append("Saved filter found")
    else:
        return {"passed": False, "score": 0, "feedback": "No saved filter named 'Chairs Only' found"}

    # Check 2: Name Exact Match (30 pts)
    # The query in export_result already filters by name="Chairs Only", but double check
    actual_name = result.get("filter_name", "")
    if actual_name == expected_name:
        score += 30
        feedback_parts.append("Filter name is correct")
    else:
        feedback_parts.append(f"Filter name mismatch (Expected: {expected_name}, Got: {actual_name})")

    # Check 3: Domain Verification (30 pts)
    # Domain is stored as a string rep of a list, e.g., "[('product_id', '=', 15)]"
    domain_str = result.get("filter_domain", "[]")
    target_pid = result.get("target_product_id", 0)
    
    domain_correct = False
    
    # Simple string checks first
    if str(target_pid) in domain_str and "product_id" in domain_str:
        domain_correct = True # Likely [('product_id', '=', PID)]
    elif "Office Chair" in domain_str and "product_id" in domain_str:
        domain_correct = True # Likely [('product_id', 'ilike', 'Office Chair')]
    
    # Advanced: Try to parse the domain list safely
    if not domain_correct:
        try:
            domain_list = ast.literal_eval(domain_str)
            for leaf in domain_list:
                # leaf is usually (field, operator, value)
                if len(leaf) == 3:
                    field, op, val = leaf
                    if field == "product_id":
                        if val == target_pid or (isinstance(val, str) and "Office Chair" in val):
                            domain_correct = True
                            break
        except Exception:
            pass # Parsing failed, stick to string check result

    if domain_correct:
        score += 30
        feedback_parts.append("Filter domain correctly targets product")
    else:
        feedback_parts.append(f"Filter domain incorrect or empty: {domain_str}")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }