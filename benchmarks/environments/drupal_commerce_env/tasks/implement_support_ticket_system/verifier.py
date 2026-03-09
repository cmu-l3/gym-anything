#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_support_ticket_system(traj, env_info, task_info):
    """
    Verifies the Support Ticket System implementation.
    
    Scoring Breakdown (100 pts total):
    1. Content Type 'support_ticket' exists: 15 pts
    2. Related Order field exists (Entity Ref): 20 pts
    3. Priority field exists (List): 15 pts
    4. Test Node 'Defective Battery' created: 15 pts
    5. Test Node linked to an Order and High priority: 15 pts
    6. Admin View exists at correct path: 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    score = 0
    feedback = []

    # 1. Content Type (15 pts)
    if result.get("content_type_exists"):
        score += 15
        feedback.append("Content Type 'support_ticket' verified.")
    else:
        feedback.append("Content Type 'support_ticket' NOT found.")

    # 2. Order Reference Field (20 pts)
    if result.get("order_field_found"):
        score += 20
        feedback.append("Order Reference field verified.")
    else:
        feedback.append("Order Reference field targeting 'commerce_order' NOT found.")

    # 3. Priority Field (15 pts)
    if result.get("priority_field_found"):
        score += 15
        feedback.append("Priority field verified.")
    else:
        feedback.append("Priority field with correct values NOT found.")

    # 4. Test Node Existence (15 pts)
    if result.get("node_found"):
        score += 15
        feedback.append("Test ticket 'Defective Battery' found.")
    else:
        feedback.append("Test ticket 'Defective Battery' NOT found.")

    # 5. Test Node Data (15 pts)
    # 10 pts for Order link, 5 pts for Priority 'High'
    data_score = 0
    if result.get("node_has_order"):
        data_score += 10
        feedback.append("Ticket is linked to an order.")
    else:
        feedback.append("Ticket is NOT linked to an order.")
    
    # Check priority value (allow 'High' or key '2' or '3' depending on impl)
    p_val = result.get("node_priority_value", "")
    if "High" in p_val or p_val == "2" or p_val == "high": 
        data_score += 5
        feedback.append("Ticket priority is 'High'.")
    else:
        feedback.append(f"Ticket priority mismatch (Found: '{p_val}').")
    
    score += data_score

    # 6. Admin View (20 pts)
    # 10 pts for path, 10 pts for filter
    view_score = 0
    if result.get("view_path_exists"):
        view_score += 10
        feedback.append("View path '/admin/support-tickets' active.")
    else:
        feedback.append("View path '/admin/support-tickets' NOT found.")
        
    if result.get("view_has_exposed_filter"):
        view_score += 10
        feedback.append("View has exposed filter.")
    else:
        feedback.append("View missing exposed filter.")
    
    score += view_score

    # Anti-gaming check
    if result.get("node_found") and not result.get("node_created_during_task"):
        feedback.append("WARNING: Test node timestamp indicates it was not created during this session.")
        # We might penalize or fail, but for now just warn in feedback
        # score = 0 # Uncomment to enforce strict anti-gaming

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }