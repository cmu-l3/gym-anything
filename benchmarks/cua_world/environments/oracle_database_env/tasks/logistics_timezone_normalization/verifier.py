#!/usr/bin/env python3
"""
Verifier for logistics_timezone_normalization task.

Verification Logic:
1. View Existence: Checks if V_FLIGHT_ANALYSIS exists in HR schema.
2. Structure: Checks for required columns (DEPART_UTC, DURATION_MINUTES).
3. Logic Check (The "Gap Week" Trap):
   - Flight 900 (JFK->LHR, Mar 15) occurs when US is DST but UK is not.
   - Time diff is 4 hours.
   - Local: 18:00 -> 06:00 (+1).
   - UTC: 22:00 -> 06:00 (+1).
   - Duration: 8 hours (480 mins).
   - Incorrect fixed offset (-5) would yield 7 hours.
4. Logic Check (Date Line):
   - Flight 100 (HND->SFO).
   - Duration must be positive (~570 mins). Naive math is negative.
5. CSV Report:
   - Must exist.
   - Must contain flight 800 (Duration ~840 mins).
   - Must NOT contain flight 900 (Duration 480 mins).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logistics_timezone_normalization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    view_data = result.get("view_data", {})
    rows = {r["flight_id"]: r for r in view_data.get("rows", [])}

    # --- Criterion 1: View Exists (10 pts) ---
    if view_data.get("view_exists"):
        score += 10
        feedback_parts.append("View V_FLIGHT_ANALYSIS exists")
    else:
        feedback_parts.append("View V_FLIGHT_ANALYSIS not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Date Line Handling (Flight 100) (25 pts) ---
    # Target: 570 mins (9.5 hrs). Allow tolerance +/- 1 min.
    f100 = rows.get(100)
    if f100:
        dur = f100.get("duration")
        if dur is not None and 569 <= float(dur) <= 571:
            score += 25
            feedback_parts.append("Date line crossing calculated correctly")
        elif dur is not None and float(dur) < 0:
            feedback_parts.append(f"Date line error: Negative duration ({dur})")
        else:
            feedback_parts.append(f"Date line error: Expected 570, got {dur}")
    else:
        feedback_parts.append("Flight 100 missing from view")

    # --- Criterion 3: Gap Week/Timezone Handling (Flight 900) (25 pts) ---
    # Target: 480 mins (8 hrs). 
    # If they hardcoded -5 for EST, result is 420 mins (7 hrs) -> Fail.
    f900 = rows.get(900)
    if f900:
        dur = f900.get("duration")
        if dur is not None and 479 <= float(dur) <= 481:
            score += 25
            feedback_parts.append("DST Gap Week calculated correctly")
        elif dur is not None and 419 <= float(dur) <= 421:
            feedback_parts.append("DST Gap Week error: Used standard offset instead of named timezone")
        else:
            feedback_parts.append(f"DST error: Expected 480, got {dur}")
    else:
        feedback_parts.append("Flight 900 missing from view")

    # --- Criterion 4: UTC Timestamps (15 pts) ---
    # Check Flight 900 Dep: 2024-03-15 22:00:00 (UTC)
    if f900:
        dep_utc = f900.get("depart_utc", "")
        if "22:00" in str(dep_utc) and "2024-03-15" in str(dep_utc):
            score += 15
            feedback_parts.append("UTC conversion correct")
        else:
            feedback_parts.append(f"UTC conversion mismatch. Expected 22:00, got {dep_utc}")

    # --- Criterion 5: CSV Report (25 pts) ---
    # Should exist and contain Flight 800 but NOT Flight 900 (800 > 800, 480 < 800)
    csv_exists = result.get("csv_exists")
    csv_content = result.get("csv_content_sample", "")
    
    if csv_exists:
        if "800" in csv_content and "900" not in csv_content:
            score += 25
            feedback_parts.append("CSV report correct")
        elif "800" in csv_content:
            score += 15
            feedback_parts.append("CSV report exists but filtering might be wrong")
        else:
            score += 10
            feedback_parts.append("CSV report exists but missing target flight")
    else:
        feedback_parts.append("CSV report not found")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }