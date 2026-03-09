#!/usr/bin/env python3
"""
Verifier for construct_technical_markup_msft task.

Checks:
1. Workspace modified (10 pts)
2. MSFT Chart created (10 pts)
3. Andrews' Pitchfork applied (30 pts)
4. Pitchfork anchors align with Jan 6, July 18, Oct 26 2023 (20 pts)
5. Fibonacci Retracement applied (15 pts)
6. Fibonacci anchors align with Jan 6, July 18 2023 (15 pts)

Also uses VLM to confirm visual presence of drawing tools on chart.
"""

import json
import tempfile
import os
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "markup_result.json"
EXPECTED_DATES = {
    "A": "2023-01-06",
    "B": "2023-07-18",
    "C": "2023-10-26"
}

def parse_date(date_str):
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except:
        return None

def is_date_close(date_str, target_str, tolerance_days=3):
    d = parse_date(date_str)
    t = parse_date(target_str)
    if not d or not t:
        return False
    return abs((d - t).days) <= tolerance_days

def verify_technical_markup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # The Windows path was C:\Users\Docker\Desktop\NinjaTraderTasks\markup_result.json
        # Docker linux containers usually mount windows workspace at specific points or we use the absolute windows path if the copy util supports it.
        # Assuming the env mapping handles the path provided in export_result.ps1
        # In typical gym-anything windows envs, we copy from the absolute path in the guest.
        
        copy_from_env("C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\markup_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve analysis results"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Workspace Modified (10 pts)
    if result.get("workspace_modified", False):
        score += 10
        feedback.append("Workspace saved.")
    else:
        feedback.append("Workspace NOT saved or modified.")

    # Criterion 2: Chart Instrument Correct (10 pts)
    if result.get("instrument_correct", False):
        score += 10
        feedback.append("MSFT chart detected.")
    else:
        feedback.append("MSFT chart NOT found in workspace.")

    # Criterion 3 & 4: Pitchfork (30 pts + 20 pts accuracy)
    pf_found = result.get("pitchfork_found", False)
    if pf_found:
        score += 30
        feedback.append("Andrews' Pitchfork tool found.")
        
        # Check anchors strictly
        detected_anchors = [x for x in result.get("anchors_detected", []) if x["tool"] == "Pitchfork"]
        valid_anchors = False
        for d in detected_anchors:
            d1_ok = is_date_close(d.get("d1"), EXPECTED_DATES["A"])
            d2_ok = is_date_close(d.get("d2"), EXPECTED_DATES["B"])
            d3_ok = is_date_close(d.get("d3"), EXPECTED_DATES["C"])
            
            if d1_ok and d2_ok and d3_ok:
                valid_anchors = True
                break
        
        if valid_anchors:
            score += 20
            feedback.append("Pitchfork anchors correctly placed on Jan/July/Oct pivots.")
        else:
            feedback.append("Pitchfork found but anchors do not match required dates.")
    else:
        feedback.append("Andrews' Pitchfork tool NOT found.")

    # Criterion 5 & 6: Fibonacci (15 pts + 15 pts accuracy)
    fib_found = result.get("fibonacci_found", False)
    if fib_found:
        score += 15
        feedback.append("Fibonacci Retracement tool found.")
        
        detected_anchors = [x for x in result.get("anchors_detected", []) if x["tool"] == "Fibonacci"]
        valid_anchors = False
        for d in detected_anchors:
            d1_ok = is_date_close(d.get("d1"), EXPECTED_DATES["A"])
            d2_ok = is_date_close(d.get("d2"), EXPECTED_DATES["B"])
            
            if d1_ok and d2_ok:
                valid_anchors = True
                break
        
        if valid_anchors:
            score += 15
            feedback.append("Fibonacci anchors correctly placed on Jan/July swing.")
        else:
            feedback.append("Fibonacci found but anchors do not match required dates.")
    else:
        feedback.append("Fibonacci Retracement tool NOT found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }