#!/usr/bin/env python3
"""Verifier for document_equipment_calibration task."""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_date_proximity(expected_str, actual_str, tolerance_days):
    """Checks if the actual date is within tolerance of the expected date."""
    if not actual_str or not expected_str:
        return False
        
    try:
        expected_date = datetime.strptime(expected_str, "%Y-%m-%d")
        actual_date = datetime.strptime(actual_str.strip(), "%Y-%m-%d")
        return abs((actual_date - expected_date).days) <= tolerance_days
    except ValueError:
        # Fallback to direct string matching if agent didn't use strict ISO formatting
        return expected_str in actual_str


def verify_document_equipment_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_status = metadata.get('expected_status', 'Operational').lower()
    expected_notes_kw = metadata.get('expected_notes_keyword', 'Slope 98%').lower()

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

    task_start = int(result.get('task_start', 0))
    db_state = result.get('db_state', {})
    
    score = 0
    feedback = []
    
    # 1. Item found check (20 pts)
    if not db_state.get('found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Item 'Mettler Toledo pH Meter' not found in database."
        }
    
    score += 20
    feedback.append("Item found")
    
    cells = db_state.get('cells', {})
    container_today = db_state.get('container_today', '')
    container_next_30 = db_state.get('container_next_30', '')
    
    status_cell = cells.get('Status', {})
    last_cal_cell = cells.get('Last Calibration', {})
    next_cal_cell = cells.get('Next Calibration', {})
    notes_cell = cells.get('Maintenance Notes', {})

    # 2. Anti-gaming check (20 pts)
    # At least one cell needs to be modified AFTER task started
    updated_after_start = False
    for cell in [status_cell, last_cal_cell, next_cal_cell, notes_cell]:
        if int(cell.get('updated_at', 0)) >= task_start:
            updated_after_start = True
            break
            
    if updated_after_start:
        score += 20
        feedback.append("Modifications detected after task start")
    else:
        feedback.append("No cell modifications detected after task start (task failed anti-gaming check)")

    # 3. Status Check (15 pts)
    status_val = str(status_cell.get('value', '')).strip().lower()
    if expected_status in status_val:
        score += 15
        feedback.append("Status updated to Operational")
    else:
        feedback.append(f"Status incorrect: got '{status_val}'")

    # 4. Last Calibration Check (15 pts)
    # Tolerance of 1 day to allow for timezone edge cases or manual entry typos
    last_cal_val = str(last_cal_cell.get('value', '')).strip()
    if check_date_proximity(container_today, last_cal_val, tolerance_days=1):
        score += 15
        feedback.append("Last Calibration updated to today")
    else:
        feedback.append(f"Last Calibration incorrect (Expected ~{container_today}, got '{last_cal_val}')")

    # 5. Next Calibration Check (15 pts)
    # Tolerance of 2 days for "exactly 30 days" manual calculation errors
    next_cal_val = str(next_cal_cell.get('value', '')).strip()
    if check_date_proximity(container_next_30, next_cal_val, tolerance_days=2):
        score += 15
        feedback.append("Next Calibration updated to +30 days")
    else:
        feedback.append(f"Next Calibration incorrect (Expected ~{container_next_30}, got '{next_cal_val}')")

    # 6. Notes Check (15 pts)
    notes_val = str(notes_cell.get('value', '')).strip().lower()
    if expected_notes_kw in notes_val:
        score += 15
        feedback.append("Notes correct")
    else:
        feedback.append(f"Notes incorrect: got '{notes_val}'")

    # Final pass threshold is 85/100
    # Meaning the agent needs to find the item, modify it, and get at least 3/4 content fields perfectly correct
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "item_found": db_state.get('found', False),
            "anti_gaming_passed": updated_after_start,
            "status_correct": expected_status in status_val,
            "last_cal_correct": check_date_proximity(container_today, last_cal_val, 1),
            "next_cal_correct": check_date_proximity(container_next_30, next_cal_val, 2),
            "notes_correct": expected_notes_kw in notes_val
        }
    }