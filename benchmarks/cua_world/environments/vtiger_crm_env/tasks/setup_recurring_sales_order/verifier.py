#!/usr/bin/env python3
"""
Verifier for setup_recurring_sales_order task.
Checks database extracts to ensure the recurring Sales Order was properly created
with correct schedules, accounts, and line items.
"""

import os
import json
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_recurring_sales_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    e_subject = metadata.get('expected_subject', '2025 Printer Lease Contract - Global Trade Corp')
    e_org = metadata.get('expected_org', 'Global Trade Corp')
    e_status = metadata.get('expected_status', 'Approved')
    e_freq = metadata.get('expected_recurring_frequency', 'Monthly')
    e_start = metadata.get('expected_start_period', '2025-01-01')
    e_end = metadata.get('expected_end_period', '2025-12-31')
    e_payment = metadata.get('expected_payment_duration', 'Net 30')
    e_inv_status = metadata.get('expected_invoice_status', 'Created')
    e_svc = metadata.get('expected_service_name', 'Enterprise Printer Lease & Maintenance')
    e_qty = float(metadata.get('expected_quantity', 1))
    e_price = float(metadata.get('expected_price', 450.00))

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/setup_recurring_sales_order_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    found = result.get('sales_order_found', False)
    if not found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Sales Order with the target subject was not found in the database."
        }

    # Criterion 1: Sales Order Basics & Anti-Gaming (20 pts)
    subject = result.get('subject', '')
    status = result.get('status', '')
    created_str = result.get('created_time', '')
    task_start = float(result.get('task_start_time', 0))
    
    is_new = True
    try:
        # Vtiger uses 'YYYY-MM-DD HH:MM:SS' in UTC
        if created_str:
            created_ts = datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S").timestamp()
            # Allow some margin for timezone differences or fast operations, but pre_task script guarantees clean slate anyway
            if created_ts < task_start - 3600:
                is_new = False
    except Exception:
        pass

    if subject == e_subject and status == e_status and is_new:
        score += 20
        feedback_parts.append("✅ Sales Order base record correctly created")
    else:
        feedback_parts.append(f"❌ Sales Order basics mismatch (Status: {status}, New: {is_new})")

    # Criterion 2: Account linked (10 pts)
    account = result.get('account_name', '')
    if account == e_org:
        score += 10
        feedback_parts.append("✅ Organization linked correctly")
    else:
        feedback_parts.append(f"❌ Organization mismatch: expected '{e_org}', got '{account}'")

    # Criterion 3: Recurring Enabled Check (10 pts)
    # Vtiger may store '1', 'on', or 'true' depending on exact schema version, so we check broadly
    recurring = str(result.get('enable_recurring', '')).lower()
    if recurring in ['1', 'on', 'true', 'yes']:
        score += 10
        feedback_parts.append("✅ Recurring flag is enabled")
    else:
        feedback_parts.append("❌ Recurring flag is NOT enabled")

    # Criterion 4: Recurring Schedule config (30 pts)
    r_freq = result.get('recurring_frequency', '')
    r_start = result.get('start_period', '')
    r_end = result.get('end_period', '')
    r_pay = result.get('payment_duration', '')
    r_stat = result.get('invoice_status', '')

    sched_matches = 0
    if r_freq.lower() == e_freq.lower(): sched_matches += 1
    if r_start == e_start: sched_matches += 1
    if r_end == e_end: sched_matches += 1
    if r_pay.lower() == e_payment.lower(): sched_matches += 1
    if r_stat.lower() == e_inv_status.lower(): sched_matches += 1

    score += (sched_matches * 6)  # 5 factors * 6 points = 30 points
    
    if sched_matches == 5:
        feedback_parts.append("✅ Recurring Schedule configured perfectly")
    else:
        feedback_parts.append(f"⚠️ Recurring Schedule partial match ({sched_matches}/5 properties correct)")

    # Criterion 5: Line Item validation (30 pts)
    i_name = result.get('item_service_name', '')
    
    try:
        i_qty = float(result.get('item_quantity', 0))
        i_price = float(result.get('item_price', 0))
    except ValueError:
        i_qty, i_price = 0.0, 0.0

    if i_name == e_svc and abs(i_qty - e_qty) < 0.01 and abs(i_price - e_price) < 0.01:
        score += 30
        feedback_parts.append("✅ Service Line Item correct")
    else:
        feedback_parts.append(f"❌ Line Item mismatch: expected '{e_svc}' (Qty: {e_qty}, Price: {e_price}), got '{i_name}' (Qty: {i_qty}, Price: {i_price})")

    # Determine Final Pass
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }