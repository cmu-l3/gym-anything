#!/usr/bin/env python3
"""
Verifier for add_lab_order task in NOSH ChartingSystem.
Verifies that the agent logged in and created a specific laboratory order.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_lab_order(traj, env_info, task_info):
    """
    Verify that the lab order was created correctly.
    
    Scoring Criteria:
    1. New order record exists for patient (35 pts)
    2. Order type is 'Laboratory' (25 pts)
    3. Test/Description matches 'CMP' or 'Comprehensive Metabolic' (25 pts)
    4. Indication notes mention 'diabetes' or 'kidney' (15 pts)
    
    Anti-gaming:
    - Duration must be > 10 seconds
    - Order count must increase
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load task result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    initial_count = int(result.get('initial_order_count', 0))
    current_count = int(result.get('current_order_count', 0))
    last_order = result.get('last_order')
    duration = int(result.get('duration_seconds', 0))
    
    # Anti-gaming check: Duration
    if duration < 10:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task completed too quickly ({duration}s). Suspected gaming."
        }

    # Criterion 1: New order exists (35 pts)
    if current_count > initial_count and last_order:
        score += 35
        feedback_parts.append("New order record created")
    else:
        feedback_parts.append("No new order record found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Analyze order details
    # Fields in NOSH orders table: orders_type, orders_description, orders_pending, orders_notes
    o_type = str(last_order.get('orders_type', '')).lower()
    o_desc = str(last_order.get('orders_description', '')).lower()
    o_pending = str(last_order.get('orders_pending', '')).lower() # Often stores test name
    o_notes = str(last_order.get('orders_notes', '')).lower()
    
    # Combined text for looser matching
    all_text = f"{o_desc} {o_pending} {o_notes}"
    
    # Criterion 2: Order Type (25 pts)
    if 'lab' in o_type:
        score += 25
        feedback_parts.append("Order type is Laboratory")
    else:
        feedback_parts.append(f"Incorrect order type: {o_type}")

    # Criterion 3: Test Name (CMP) (25 pts)
    # Check both description and pending fields as user input might go into either
    if 'cmp' in all_text or 'comprehensive metabolic' in all_text:
        score += 25
        feedback_parts.append("Test description correct (CMP)")
    else:
        feedback_parts.append("Test description missing CMP/Comprehensive Metabolic Panel")

    # Criterion 4: Clinical Indication (15 pts)
    if 'diabet' in all_text or 'kidney' in all_text or 'ckd' in all_text:
        score += 15
        feedback_parts.append("Clinical indication found")
    else:
        feedback_parts.append("Clinical indication missing keywords (diabetes/kidney)")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "initial": initial_count,
            "current": current_count,
            "last_order": last_order
        }
    }