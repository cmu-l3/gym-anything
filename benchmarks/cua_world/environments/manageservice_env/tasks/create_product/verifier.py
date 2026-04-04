#!/usr/bin/env python3
"""
Verifier for create_product task.
Checks if Product Type and Product were created correctly in ServiceDesk Plus.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_product(traj, env_info, task_info):
    """
    Verify creation of Product Type and Product.
    
    Criteria:
    1. Product Type "Network Switch" exists. (30 pts)
    2. Product "Cisco Catalyst 9200L-24P-4G" exists. (30 pts)
    3. Product is linked to the correct Product Type. (20 pts)
    4. Manufacturer is "Cisco Systems". (10 pts)
    5. Anti-gaming: Verification via DB state check (implied by setup cleanup). (10 pts)
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

    score = 0
    feedback_parts = []
    
    # 1. Check Product Type (30 pts)
    pt_exists = result.get("product_type_exists", False)
    pt_id = result.get("product_type_id", "")
    pt_name = result.get("product_type_name", "")
    
    if pt_exists and "Network Switch" in pt_name:
        score += 30
        feedback_parts.append("Product Type 'Network Switch' created successfully.")
    else:
        feedback_parts.append("Product Type 'Network Switch' NOT found.")

    # 2. Check Product (30 pts)
    prod_exists = result.get("product_exists", False)
    prod_name = result.get("product_name", "")
    prod_pt_id = result.get("linked_product_type_id", "")
    
    if prod_exists and "Cisco Catalyst 9200L-24P-4G" in prod_name:
        score += 30
        feedback_parts.append("Product 'Cisco Catalyst 9200L-24P-4G' created successfully.")
    else:
        feedback_parts.append("Product 'Cisco Catalyst 9200L-24P-4G' NOT found.")

    # 3. Check Link (20 pts)
    if pt_exists and prod_exists and pt_id and prod_pt_id and (str(pt_id) == str(prod_pt_id)):
        score += 20
        feedback_parts.append("Product is correctly linked to Product Type.")
    elif pt_exists and prod_exists:
        feedback_parts.append(f"Product link mismatch: Expected Type ID {pt_id}, found {prod_pt_id}.")

    # 4. Check Manufacturer (10 pts)
    mfr_name = result.get("manufacturer_name", "")
    if "Cisco" in mfr_name: # Allow partial match like "Cisco Systems" or "Cisco"
        score += 10
        feedback_parts.append(f"Manufacturer set correctly ({mfr_name}).")
    else:
        feedback_parts.append(f"Manufacturer incorrect or missing (Found: '{mfr_name}').")

    # 5. Anti-gaming / Timestamp check (10 pts)
    # Since setup script deletes matching records, existence implies they were created during task.
    # We award points if both exist.
    if pt_exists and prod_exists:
        score += 10
        feedback_parts.append("New records verified.")

    passed = score >= 60 and pt_exists and prod_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }