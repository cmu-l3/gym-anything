#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rfq(traj, env_info, task_info):
    """
    Verifies the Create RfQ task.
    Criteria:
    1. RfQ Topic 'Spring Furniture Restock' exists.
    2. RfQ Document created and linked to topic.
    3. RfQ Line exists with 'Patio Chair' and Qty 20.
    4. At least 2 Subscribers added.
    5. RfQ Status is Completed.
    6. Created during task session.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract data
    topic_found = result.get('topic_found', False)
    rfq_found = result.get('rfq_found', False)
    docstatus = result.get('rfq_docstatus', '')
    product_name = result.get('product_name', '')
    qty = result.get('qty', 0)
    subscriber_count = result.get('subscriber_count', 0)
    created_during_task = result.get('created_during_task', False)
    
    metadata = task_info.get('metadata', {})
    expected_product = metadata.get('expected_product_name', 'Patio Chair')
    expected_qty = metadata.get('expected_qty', 20)
    min_subscribers = metadata.get('min_subscriber_count', 2)

    score = 0
    feedback = []

    # Criterion 1: Topic Created (20 pts)
    if topic_found:
        score += 20
        feedback.append("Topic 'Spring Furniture Restock' created.")
    else:
        feedback.append("Failed: RfQ Topic 'Spring Furniture Restock' not found.")

    # Criterion 2: RfQ Document Created & Timing (20 pts)
    if rfq_found:
        if created_during_task:
            score += 20
            feedback.append("RfQ document created.")
        else:
            score += 5
            feedback.append("RfQ document found but timestamp indicates it was pre-existing.")
    else:
        feedback.append("Failed: No RfQ document found linked to the topic.")

    # Criterion 3: Correct Product and Qty (20 pts)
    # Flexible matching for product name
    if expected_product.lower() in product_name.lower():
        if abs(qty - expected_qty) < 0.01:
            score += 20
            feedback.append(f"Correct product ({product_name}) and quantity ({qty}).")
        else:
            score += 10
            feedback.append(f"Correct product but wrong quantity (Expected {expected_qty}, got {qty}).")
    else:
        feedback.append(f"Failed: Product mismatch (Expected '{expected_product}', got '{product_name}').")

    # Criterion 4: Subscribers (20 pts)
    if subscriber_count >= min_subscribers:
        score += 20
        feedback.append(f"Subscribers added ({subscriber_count}).")
    elif subscriber_count > 0:
        score += 10
        feedback.append(f"Insufficient subscribers ({subscriber_count}/{min_subscribers}).")
    else:
        feedback.append("Failed: No subscribers added.")

    # Criterion 5: Document Status (20 pts)
    if docstatus == 'CO':
        score += 20
        feedback.append("RfQ is Completed.")
    elif docstatus == 'DR':
        feedback.append("RfQ is still in Draft status (not Completed).")
    else:
        feedback.append(f"RfQ status is {docstatus}.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }