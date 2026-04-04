#!/usr/bin/env python3
"""
Verifier for find_peak_demand task.
Checks if the agent correctly identified the peak power and timestamp.
"""

import json
import tempfile
import os
import re

def verify_find_peak_demand(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check if report file exists (15 pts)
    if not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file ~/peak_demand_report.txt not found"}
    score += 15
    feedback.append("Report file found (+15)")

    # 2. Check anti-gaming timestamp (10 pts)
    if result.get("report_created_during_task"):
        score += 10
        feedback.append("File created during task (+10)")
    else:
        feedback.append("Warning: File modification time predates task start")

    # 3. Parse content
    content = result.get("report_content", "")
    ground_truth = result.get("ground_truth", {})
    
    true_watts = ground_truth.get("peak_watts")
    true_time = ground_truth.get("peak_timestamp")

    if true_watts is None or true_time is None:
        return {"passed": False, "score": 0, "feedback": "System Error: Ground truth missing"}

    # Extract values using regex
    # Looking for: peak_watts: 1234.56
    watt_match = re.search(r"peak_watts:\s*([\d\.]+)", content, re.IGNORECASE)
    time_match = re.search(r"peak_timestamp:\s*(\d+)", content, re.IGNORECASE)

    # 4. Verify Peak Watts (40 pts)
    watts_correct = False
    if watt_match:
        try:
            reported_watts = float(watt_match.group(1))
            # Tolerance +/- 1.0 Watt
            if abs(reported_watts - true_watts) <= 1.0:
                score += 40
                watts_correct = True
                feedback.append(f"Peak power correct: {reported_watts} (True: {true_watts}) (+40)")
            else:
                feedback.append(f"Peak power incorrect. Reported: {reported_watts}, Expected: {true_watts}")
        except ValueError:
            feedback.append("Could not parse watts value")
    else:
        feedback.append("Format error: 'peak_watts:' line not found")

    # 5. Verify Timestamp (25 pts)
    time_correct = False
    if time_match:
        try:
            reported_time = int(time_match.group(1))
            # Tolerance +/- 600 seconds (one interval)
            # Sometimes graph tooltips snap to nearest interval
            if abs(reported_time - true_time) <= 600:
                score += 25
                time_correct = True
                feedback.append(f"Timestamp correct: {reported_time} (True: {true_time}) (+25)")
            else:
                feedback.append(f"Timestamp incorrect. Reported: {reported_time}, Expected: {true_time}")
        except ValueError:
            feedback.append("Could not parse timestamp value")
    else:
        feedback.append("Format error: 'peak_timestamp:' line not found")

    # 6. Valid Format Bonus (10 pts)
    if watt_match and time_match:
        score += 10
        feedback.append("File format correct (+10)")

    passed = (score >= 65) and watts_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }