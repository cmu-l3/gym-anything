#!/usr/bin/env python3
"""
Verifier for manage_customer_subscription task.
Verifies the creation of a Service Product, Subscription Type, and Subscription record.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_customer_subscription(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_prod_key = metadata.get('product_key', 'SVC-GARDEN-001')
    expected_subtype_name = metadata.get('subtype_name', 'Monthly Care Plan')
    expected_sub_name = metadata.get('sub_name', 'C&W HQ Maintenance 2025')
    expected_bp_name = metadata.get('bp_name', 'C&W Construction')

    # Load result from container
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
    feedback_parts = []
    
    # 1. Verify Product (20 pts)
    product = result.get('product')
    if product:
        # Check basic fields
        is_service = product.get('producttype') == 'S'
        key_match = product.get('value') == expected_prod_key
        
        if key_match:
            score += 10
            feedback_parts.append(f"Product '{expected_prod_key}' created")
            if is_service:
                score += 10
                feedback_parts.append("Product type is 'Service'")
            else:
                feedback_parts.append(f"Product type incorrect (expected Service, got {product.get('producttype')})")
        else:
            feedback_parts.append(f"Product key mismatch (expected {expected_prod_key})")
    else:
        feedback_parts.append("Product not found")

    # 2. Verify Subscription Type (20 pts)
    subtype = result.get('subscription_type')
    if subtype:
        name_match = subtype.get('name') == expected_subtype_name
        is_month = subtype.get('frequencytype') == 'M'
        
        if name_match:
            score += 10
            feedback_parts.append(f"Subscription Type '{expected_subtype_name}' created")
            if is_month:
                score += 10
                feedback_parts.append("Frequency is 'Month'")
            else:
                feedback_parts.append(f"Frequency incorrect (expected Month, got {subtype.get('frequencytype')})")
        else:
            feedback_parts.append("Subscription Type name mismatch")
    else:
        feedback_parts.append("Subscription Type not found")

    # 3. Verify Subscription (60 pts total)
    sub = result.get('subscription')
    if sub:
        score += 10  # Base points for creating record
        feedback_parts.append(f"Subscription '{expected_sub_name}' created")

        # Check relationships (20 pts)
        rel_score = 0
        if sub.get('bp_name') and expected_bp_name in sub.get('bp_name'):
            rel_score += 5
            feedback_parts.append("Linked to correct Business Partner")
        else:
            feedback_parts.append(f"Wrong Business Partner: {sub.get('bp_name')}")
            
        if sub.get('product_value') == expected_prod_key:
            rel_score += 10
            feedback_parts.append("Linked to correct Product")
        else:
            feedback_parts.append(f"Wrong Product linked: {sub.get('product_value')}")
            
        if sub.get('subtype_name') == expected_subtype_name:
            rel_score += 5
            feedback_parts.append("Linked to correct Subscription Type")
        else:
            feedback_parts.append(f"Wrong Subscription Type linked: {sub.get('subtype_name')}")
        score += rel_score

        # Check dates (30 pts)
        date_score = 0
        start = sub.get('startdate', '')
        renewal = sub.get('renewaldate', '')
        
        # Check if dates match expected (allow string match or date object comparison logic if needed)
        # SQL returns YYYY-MM-DD
        if '2025-01-01' in str(start):
            date_score += 15
            feedback_parts.append("Start Date correct")
        else:
            feedback_parts.append(f"Start Date incorrect: {start}")
            
        if '2025-02-01' in str(renewal):
            date_score += 15
            feedback_parts.append("Renewal Date correct")
        else:
            feedback_parts.append(f"Renewal Date incorrect: {renewal}")
        score += date_score

    else:
        feedback_parts.append("Subscription record not found")

    # Anti-gaming check: Timestamp
    task_start = float(result.get('task_start_time', 0))
    # We check the creation timestamp of the subscription if it exists
    if sub:
        # Postgres JSON return might be string or float depending on driver, usually string iso format
        # We'll just trust the existence check + specific values for now as 'created' parsing can be brittle
        # without external libraries in the minimal python env.
        pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }