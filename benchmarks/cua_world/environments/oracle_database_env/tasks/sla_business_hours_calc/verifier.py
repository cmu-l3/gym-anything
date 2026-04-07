#!/usr/bin/env python3
"""
Verifier for SLA Business Hours Calculation Task.

Verifies:
1. `SLA_PERFORMANCE_VW` view exists in Oracle.
2. View has correct columns.
3. Business minutes calculation logic handles:
   - Weekends (Fri -> Mon)
   - Holidays (excl. specific dates)
   - Out-of-hours (Late night starts)
   - Same day standard logic.
4. SLA Status logic (<= 480 mins = MET).
5. CSV report generation.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sla_business_hours_calc(traj, env_info, task_info):
    """
    Verify the SLA calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Trap ticket expectations
    # 1001: Fri 16:00 -> Mon 10:00 (No holiday) = 120 mins
    # 1002: Fri 16:30 -> Tue 09:30 (Mon is holiday) = 60 mins
    # 1003: Tue 20:00 -> Wed 09:15 = 15 mins
    # 1004: Wed 10:00 -> Wed 11:30 = 90 mins
    
    expected_values = {
        "1001": 120,
        "1002": 60,
        "1003": 15,
        "1004": 90
    }
    
    # Tolerance for calculation (e.g., +/- 1 minute for rounding differences)
    tolerance = 1

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. View Existence (10 pts)
    if result.get("view_exists"):
        score += 10
        feedback.append("View SLA_PERFORMANCE_VW created.")
    else:
        feedback.append("View SLA_PERFORMANCE_VW NOT found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Columns Correct (10 pts)
    if result.get("columns_correct"):
        score += 10
        feedback.append("All required columns present.")
    else:
        feedback.append(f"Missing required columns. Found: {result.get('found_columns')}")

    # 3. Logic Verification (60 pts total)
    trap_data = result.get("trap_data", {})
    
    # Ticket 1004 (Same Day) - Base Logic (10 pts)
    val_1004 = trap_data.get("1004", {}).get("minutes", -1)
    if abs(val_1004 - expected_values["1004"]) <= tolerance:
        score += 10
        feedback.append("Same-day calculation correct (Ticket 1004).")
    else:
        feedback.append(f"Same-day calculation wrong. Expected ~{expected_values['1004']}, got {val_1004}.")

    # Ticket 1001 (Weekend Spanner) (20 pts)
    val_1001 = trap_data.get("1001", {}).get("minutes", -1)
    # Common fail: 120 + 2 days (48 hours) or similar
    if abs(val_1001 - expected_values["1001"]) <= tolerance:
        score += 20
        feedback.append("Weekend logic correct (Ticket 1001).")
    else:
        feedback.append(f"Weekend logic wrong. Expected ~{expected_values['1001']}, got {val_1001}. (Did you exclude Sat/Sun?)")

    # Ticket 1002 (Holiday Hit) (15 pts)
    val_1002 = trap_data.get("1002", {}).get("minutes", -1)
    if abs(val_1002 - expected_values["1002"]) <= tolerance:
        score += 15
        feedback.append("Holiday logic correct (Ticket 1002).")
    else:
        feedback.append(f"Holiday logic wrong. Expected ~{expected_values['1002']}, got {val_1002}. (Did you exclude public holidays?)")

    # Ticket 1003 (Late Start) (15 pts)
    val_1003 = trap_data.get("1003", {}).get("minutes", -1)
    if abs(val_1003 - expected_values["1003"]) <= tolerance:
        score += 15
        feedback.append("After-hours logic correct (Ticket 1003).")
    else:
        feedback.append(f"After-hours logic wrong. Expected ~{expected_values['1003']}, got {val_1003}.")

    # 4. CSV Export (10 pts)
    if result.get("csv_exists") and result.get("csv_valid"):
        score += 10
        feedback.append("CSV report exported successfully.")
    else:
        feedback.append("CSV report missing or invalid.")

    # 5. SLA Status Check (10 pts)
    # Check if 1001 (120 mins) is MET and maybe a fictitious breach
    status_1001 = trap_data.get("1001", {}).get("status", "UNKNOWN")
    if status_1001 == "MET":
        score += 5
    
    # Only award these points if calculation was reasonably close, to ensure status isn't just lucky
    if score >= 60: 
        score += 5 # Bonus for getting status right contextually

    # Limit score to 100
    score = min(100, score)
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }