#!/usr/bin/env python3
"""
Verifier for process_landed_cost task.
Verifies that:
1. Material Receipt created for 100 Oak Trees.
2. Vendor Invoice created for $250 Freight.
3. Landed Cost Allocation created linking the two.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_landed_cost(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check Receipt (20 points)
    receipt = result.get('receipt', {})
    if receipt.get('found'):
        status = receipt.get('status', '')
        if status in ['CO', 'CL']:
            score += 20
            feedback_parts.append("Receipt created and completed")
        else:
            score += 10
            feedback_parts.append(f"Receipt created but status is {status} (expected CO/CL)")
    else:
        feedback_parts.append("Material Receipt for 100 Oak Trees NOT found")

    # Check Invoice (20 points)
    invoice = result.get('invoice', {})
    if invoice.get('found'):
        status = invoice.get('status', '')
        if status in ['CO', 'CL']:
            score += 20
            feedback_parts.append("Freight Invoice created and completed")
        else:
            score += 10
            feedback_parts.append(f"Invoice created but status is {status}")
    else:
        feedback_parts.append("Freight Invoice for $250 NOT found")

    # Check Allocation (60 points split)
    allocation = result.get('allocation', {})
    if allocation.get('found'):
        # Just finding it means the link exists (query enforces the join)
        score += 30 # For existing and linking correct docs
        
        processed = allocation.get('processed', 'N')
        if processed == 'Y':
            score += 30
            feedback_parts.append("Landed Cost Allocation successfully processed")
        else:
            feedback_parts.append("Landed Cost Allocation created but NOT processed")
    else:
        feedback_parts.append("Landed Cost Allocation linking Receipt and Invoice NOT found")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }