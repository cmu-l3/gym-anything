#!/usr/bin/env python3
"""
Verifier for Logistics AQ Setup task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logistics_aq_setup(traj, env_info, task_info):
    """
    Verifies that the Oracle AQ infrastructure was set up and populated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/logistics_aq_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Object Type (10 pts)
    if result.get("type_exists"):
        score += 10
        feedback.append("Object Type ORDER_EVENT_T exists (+10)")
    else:
        feedback.append("Object Type ORDER_EVENT_T missing")

    # 2. Queue Table (15 pts)
    if result.get("queue_table_exists"):
        score += 15
        feedback.append("Queue Table ORDER_EVT_QT exists (+15)")
    else:
        feedback.append("Queue Table ORDER_EVT_QT missing")

    # 3. Queue Created & Enabled (15 pts)
    if result.get("queue_exists"):
        if result.get("queue_enabled"):
            score += 15
            feedback.append("Queue ORDER_EVT_Q exists and is enabled (+15)")
        else:
            score += 5
            feedback.append("Queue ORDER_EVT_Q exists but is NOT enabled (+5)")
    else:
        feedback.append("Queue ORDER_EVT_Q missing")

    # 4. Procedure Exists (10 pts)
    if result.get("procedure_exists") and result.get("procedure_status") == "VALID":
        score += 10
        feedback.append("Procedure ENQUEUE_ORDER exists and is VALID (+10)")
    elif result.get("procedure_exists"):
        score += 5
        feedback.append("Procedure ENQUEUE_ORDER exists but is INVALID (+5)")
    else:
        feedback.append("Procedure ENQUEUE_ORDER missing")

    # 5. Message Count (20 pts)
    count = result.get("message_count", 0)
    if count == 5:
        score += 20
        feedback.append("Queue contains exactly 5 messages (+20)")
    elif count > 0:
        score += 10
        feedback.append(f"Queue contains {count} messages (expected 5) (+10)")
    else:
        feedback.append("Queue is empty")

    # 6. Data Integrity (20 pts)
    # Check Order 1001 -> AMZN_PRIME
    # Check Order 1004 -> DHL_EXPRESS
    messages = result.get("messages_verified", {})
    
    # Robust check: keys might be strings "1001"
    cust_1001 = messages.get("1001")
    cust_1004 = messages.get("1004")

    if cust_1001 == "AMZN_PRIME":
        score += 10
        feedback.append("Order 1001 verified correctly (+10)")
    else:
        feedback.append(f"Order 1001 incorrect or missing (Found: {cust_1001})")

    if cust_1004 == "DHL_EXPRESS":
        score += 10
        feedback.append("Order 1004 verified correctly (+10)")
    else:
        feedback.append(f"Order 1004 incorrect or missing (Found: {cust_1004})")

    # 7. Output File (10 pts)
    if result.get("output_file_exists"):
        content = result.get("output_file_content", "")
        if "1001" in content and "AMZN_PRIME" in content:
            score += 10
            feedback.append("Output file created and contains valid data (+10)")
        else:
            score += 5
            feedback.append("Output file exists but content seems incomplete (+5)")
    else:
        feedback.append("Output file queue_dump.txt missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }