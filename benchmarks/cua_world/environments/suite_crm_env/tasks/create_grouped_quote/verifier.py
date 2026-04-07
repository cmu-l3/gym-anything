#!/usr/bin/env python3
"""
Verifier for Create Grouped Sales Quote task.

Checks:
1. Quote was newly created during the session
2. Quote header fields are correct (Title, Account)
3. Both groups exist (Software Subscriptions, Professional Services)
4. Line items are accurately populated under their respective groups
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_grouped_quote(traj, env_info, task_info):
    """
    Verify the grouped quote was properly created with correct hierarchy and pricing.
    Uses copy_from_env to safely retrieve the JSON exported by export_result.sh.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_grouped_quote_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Anti-gaming: Ensure quote count actually increased
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count <= initial_count:
        feedback.append("FAIL: No new quotes were created during this session.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    db_data = result.get('db_data', {})
    if not db_data.get('quote_found'):
        feedback.append("FAIL: Target Quote 'Q3 Infrastructure Quote - Tech Data' not found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Header exists
    score += 20
    feedback.append("Quote header created successfully")

    # 2. Account Linked (10 pts)
    if db_data.get('account_linked') and "Tech Data" in db_data.get('account_name', ''):
        score += 10
        feedback.append("Account 'Tech Data Corporation' linked correctly")
    else:
        feedback.append("Account not linked correctly")

    groups = db_data.get('groups', [])
    line_items = db_data.get('line_items', [])

    # 3. Software Subscriptions Group (15 pts)
    software_group = next((g for g in groups if "Software" in g.get('name', '')), None)
    if software_group:
        score += 15
        feedback.append("Software group exists")

        # 4. Software Line Item (20 pts)
        software_item = next((l for l in line_items if l.get('group_id') == software_group['id'] and "Red Hat" in l.get('name', '')), None)
        if software_item:
            try:
                qty = float(software_item.get('product_qty', 0))
                price = float(software_item.get('product_list_price', 0))
                if abs(qty - 20) < 0.1 and abs(price - 799) < 0.1:
                    score += 20
                    feedback.append("Software line item correct (Qty 20, Price 799)")
                else:
                    feedback.append(f"Software item has incorrect qty/price (Qty: {qty}, Price: {price})")
            except ValueError:
                feedback.append("Invalid qty/price values in Software item")
        else:
            feedback.append("Software line item missing or not correctly grouped inside Software Subscriptions")
    else:
        feedback.append("Software Subscriptions group not found")

    # 5. Professional Services Group (15 pts)
    services_group = next((g for g in groups if "Services" in g.get('name', '')), None)
    if services_group:
        score += 15
        feedback.append("Services group exists")

        # 6. Services Line Item (20 pts)
        services_item = next((l for l in line_items if l.get('group_id') == services_group['id'] and "Architecture" in l.get('name', '')), None)
        if services_item:
            try:
                qty = float(services_item.get('product_qty', 0))
                price = float(services_item.get('product_list_price', 0))
                if abs(qty - 40) < 0.1 and abs(price - 185) < 0.1:
                    score += 20
                    feedback.append("Services line item correct (Qty 40, Price 185)")
                else:
                    feedback.append(f"Services item has incorrect qty/price (Qty: {qty}, Price: {price})")
            except ValueError:
                feedback.append("Invalid qty/price values in Services item")
        else:
            feedback.append("Services line item missing or not correctly grouped inside Professional Services")
    else:
        feedback.append("Professional Services group not found")

    # Ensure max score caps at 100
    score = min(score, 100)

    # Threshold for passing is 80 (Meaning both groups had to be created properly)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }