#!/usr/bin/env python3
"""
Verifier for discontinue_medication task.
"""

import json
import logging
import tempfile
import os
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO8601-like date strings."""
    if not date_str:
        return None
    # Format usually: 2023-10-25T10:30:00.000+0000
    # Python < 3.7 doesn't handle the timezone format +0000 nicely with strptime %z sometimes
    # Simplification: strip timezone for timestamp comparison if it's just verification
    try:
        # standard iso format
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        try:
             # Try without micros
            return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S%z")
        except:
             # Fallback: ignore timezone part for simple logic
             return datetime.strptime(date_str[:19], "%Y-%m-%dT%H:%M:%S")

def verify_discontinue_medication(traj, env_info, task_info):
    """
    Verifies if the Paracetamol order was discontinued.
    
    Criteria:
    1. Patient 'Sarah Johnson' exists.
    2. A Paracetamol order exists for this patient.
    3. The order has 'dateStopped' timestamp.
    4. 'dateStopped' > task_start_time (ensure it was done NOW, not pre-existing).
    5. A valid reason was provided (orderReason or orderReasonNonCoded).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Basic Checks
    if not data.get("patient_found"):
        return {"passed": False, "score": 0, "feedback": "Patient Sarah Johnson not found in system."}
    
    orders = data.get("orders", [])
    task_start_ts = data.get("task_start_time", 0)
    
    if not orders:
        return {"passed": False, "score": 0, "feedback": "No Paracetamol orders found for patient."}
        
    # Check for discontinued order
    discontinued_order = None
    reason_valid = False
    
    for order in orders:
        date_stopped_str = order.get("dateStopped")
        if date_stopped_str:
            dt_stopped = parse_openmrs_date(date_stopped_str)
            # Convert timestamp to comparable
            if dt_stopped.timestamp() > task_start_ts:
                discontinued_order = order
                
                # Check Reason
                # Can be coded (dict) or non-coded (string)
                if order.get("orderReason") or order.get("orderReasonNonCoded"):
                    reason_valid = True
                break
    
    # Scoring
    score = 0
    feedback = []
    
    if discontinued_order:
        score += 70
        feedback.append("Paracetamol order successfully discontinued.")
        
        if reason_valid:
            score += 30
            feedback.append("Reason for discontinuation recorded.")
        else:
            feedback.append("No reason recorded for discontinuation (Partial deduction).")
            
    else:
        # Check if there was an active order at all to verify setup wasn't broken
        active_orders = [o for o in orders if not o.get("dateStopped")]
        if active_orders:
            feedback.append("Paracetamol order is still active.")
        else:
            # Maybe the agent never started, or setup failed to create active order?
            # But setup script creates it.
            # It's possible the order was stopped BEFORE task start?
            # Check timestamps of stopped orders
            pre_stopped = [o for o in orders if o.get("dateStopped")]
            if pre_stopped:
                feedback.append("Order was stopped before task started (Anti-gaming check failed).")
            else:
                feedback.append("No active or stopped Paracetamol orders found (System state error).")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }