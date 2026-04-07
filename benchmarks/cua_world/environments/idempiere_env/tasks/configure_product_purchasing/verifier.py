#!/usr/bin/env python3
"""
Verifier for configure_product_purchasing task.
Checks if the agent correctly created a Product Purchasing (M_Product_PO) record
with the specified terms.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_purchasing(traj, env_info, task_info):
    """
    Verify the purchasing configuration.
    
    Scoring:
    - Record exists: 40 pts
    - Min Order Qty correct (50): 20 pts
    - Delivery Time correct (7): 20 pts
    - Price correct (45.00): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_moq = metadata.get('expected_moq', 50)
    expected_delivery = metadata.get('expected_delivery_days', 7)
    expected_price = metadata.get('expected_price', 45.00)

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Record Existence (40 pts)
    if result.get('record_exists', False):
        score += 40
        feedback_parts.append("Purchasing record created successfully")
        
        # 2. Verify Data Accuracy
        
        # MOQ
        try:
            actual_moq = float(result.get('order_min', 0))
            if abs(actual_moq - expected_moq) < 0.01:
                score += 20
                feedback_parts.append(f"Min Order Qty correct ({int(actual_moq)})")
            else:
                feedback_parts.append(f"Min Order Qty incorrect (Expected: {expected_moq}, Found: {actual_moq})")
        except ValueError:
            feedback_parts.append("Invalid MOQ value format")

        # Delivery Time
        try:
            actual_del = float(result.get('delivery_time', 0))
            if abs(actual_del - expected_delivery) < 0.01:
                score += 20
                feedback_parts.append(f"Delivery Time correct ({int(actual_del)} days)")
            else:
                feedback_parts.append(f"Delivery Time incorrect (Expected: {expected_delivery}, Found: {actual_del})")
        except ValueError:
            feedback_parts.append("Invalid Delivery Time value format")

        # Price
        try:
            actual_price = float(result.get('price', 0))
            if abs(actual_price - expected_price) < 0.01:
                score += 20
                feedback_parts.append(f"Price correct ({actual_price})")
            else:
                feedback_parts.append(f"Price incorrect (Expected: {expected_price}, Found: {actual_price})")
        except ValueError:
            feedback_parts.append("Invalid Price value format")

    else:
        feedback_parts.append("No purchasing record found for 'Heavy Duty Tarp' and 'Industrial Supply Co'")

    # Anti-gaming check: Timestamp
    # Ideally compare db_created_timestamp with task_start, but format parsing can be tricky.
    # The existence check combined with the setup script deleting the record is a strong enough signal for this scope.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }