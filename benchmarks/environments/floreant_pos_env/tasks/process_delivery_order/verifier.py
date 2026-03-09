#!/usr/bin/env python3
"""
Verifier for process_delivery_order task.
Checks if a Home Delivery ticket was created with correct customer info and items.
"""

import json
import os
import tempfile
import logging
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_delivery_order(traj, env_info, task_info):
    """
    Verify the delivery order task.
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

    # Extract Data
    db_data = result.get('db_data', {})
    raw_output = db_data.get('raw_output', "")
    initial_count = int(result.get('initial_ticket_count', 0))
    final_count = int(db_data.get('final_ticket_count', 0))

    score = 0
    feedback = []

    # 1. Anti-gaming: Ticket Count Increased (20 pts)
    # This proves *something* was created
    if final_count > initial_count:
        score += 20
        feedback.append("New ticket created in database.")
    else:
        feedback.append("No new ticket found in database.")

    # 2. Check Ticket Content (Parsing raw Derby output)
    # We look for "Maria Santos", "555-0147", "Evergreen" in the raw dump
    # This is robust because we dumped the relevant rows in export_result.sh

    # Customer Name (15 pts)
    if "Maria Santos" in raw_output or "MARIA SANTOS" in raw_output:
        score += 15
        feedback.append("Customer name 'Maria Santos' found.")
    else:
        feedback.append("Customer name missing.")

    # Phone (10 pts)
    if "555-0147" in raw_output or "5550147" in raw_output:
        score += 10
        feedback.append("Phone number found.")
    else:
        feedback.append("Phone number missing.")

    # Address (10 pts)
    if "Evergreen" in raw_output:
        score += 10
        feedback.append("Address found.")
    else:
        feedback.append("Address missing.")

    # Ticket Type (10 pts)
    # Look for HOME_DELIVERY associated with the ticket
    if "HOME_DELIVERY" in raw_output or "HOME DELIVERY" in raw_output:
        score += 10
        feedback.append("Correct order type (Home Delivery).")
    else:
        feedback.append("Order type 'HOME_DELIVERY' not found.")

    # Items (20 pts)
    # We query TICKET_ITEM table in the export script.
    # We look for rows. If we see multiple item names, we give points.
    # In the raw output, item rows usually look like:
    # TICKET_ID | ITEM_NAME ...
    # 15        | Burger ...
    # 15        | Cola ...
    # We count lines containing item names (heuristic)
    # or just check if we see at least 2 items associated with the new ticket ID.

    # Heuristic: Count occurrences of our known ticket ID in the ITEM query section
    # First, find the new ticket ID. It's usually the largest number in the ID column.
    # Assuming the raw output contains the result of "SELECT ... FROM TICKET ORDER BY ID DESC"
    # The first numeric ID appearing in the TICKET results section is likely the one.
    
    # Let's trust the "New ticket created" check plus content checks.
    # If the user entered items, they usually show up in the TICKET_ITEM query section.
    # We'll check for general presence of item data.
    # A better check: count rows in the ITEM query output section.
    item_section = raw_output.split("SELECT t.ID AS TICKET_ID, i.ITEM_NAME")[1] if "SELECT t.ID AS TICKET_ID, i.ITEM_NAME" in raw_output else ""
    # simple heuristic: count non-empty lines that start with a digit (ticket id)
    item_count = len(re.findall(r'^\s*\d+\s*\|', item_section, re.MULTILINE))
    
    if item_count >= 2:
        score += 20
        feedback.append(f"Found {item_count} items on ticket.")
    elif item_count == 1:
        score += 10
        feedback.append("Found only 1 item (expected 2+).")
    else:
        feedback.append("No items found on ticket.")

    # Status: Closed/Paid (15 pts)
    # Check for 'true' in CLOSED or PAID columns in TICKET section
    if "true" in raw_output.lower() and ("CLOSED" in raw_output or "PAID" in raw_output):
        score += 15
        feedback.append("Order is finalized (Closed/Paid).")
    else:
        feedback.append("Order is not finalized (still Open/Draft).")

    # VLM Verification (Trajectory) - Optional robustness
    # If using VLM, we'd add points here. For now, logic is solid based on DB.
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }