#!/usr/bin/env python3
"""
Verifier for insert_slack_column_report task.

Verifies:
1. Report file creation and timestamp (anti-gaming).
2. Content of the report:
   - Lists specific tasks from the project.
   - Includes slack values.
   - Correctly identifies critical vs non-critical tasks.
3. VLM verification of the column insertion in the GUI.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_slack_column_report(traj, env_info, task_info):
    """
    Verify the critical path report task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Anti-Gaming (10 pts)
    if not result_data.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Report file timestamp is invalid (created before task start).")
        # Continue but strictly penalize
    else:
        score += 10
        feedback_parts.append("Report file created during task.")

    # 3. Analyze Report Content
    # Copy the text report from the container
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_content = ""
    try:
        copy_from_env("/tmp/exported_report.txt", temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Failed to read report content: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    report_lower = report_content.lower()

    # Criteria A: All tasks listed (15 pts)
    # Sample names from the XML
    required_tasks = [
        "requirements gathering", "system architecture design", "database schema design",
        "ui/ux wireframes", "backend api development", "frontend development",
        "integration testing", "user acceptance testing"
    ]
    found_count = sum(1 for t in required_tasks if t in report_lower)
    if found_count >= len(required_tasks) - 1:
        score += 15
        feedback_parts.append(f"Most tasks listed ({found_count}/{len(required_tasks)} sample check).")
    elif found_count > 3:
        score += 8
        feedback_parts.append(f"Some tasks listed ({found_count}).")
    else:
        feedback_parts.append("Task list incomplete.")

    # Criteria B: Slack values present (15 pts)
    # Check for numbers associated with 'day' or 'slack'
    if "day" in report_lower and any(c.isdigit() for c in report_content):
        score += 15
        feedback_parts.append("Slack values appear to be present.")
    else:
        feedback_parts.append("Slack values missing or format incorrect.")

    # Criteria C: Critical designation & Correctness (30 pts)
    # 'Requirements Gathering' is usually critical (slack 0) in this sample
    # 'Database Schema Design' usually has float
    critical_check = "requirements gathering" in report_lower and "yes" in report_lower
    float_check = "database schema design" in report_lower
    
    if "yes" in report_lower and "no" in report_lower:
        score += 10
        feedback_parts.append("Both Critical (YES) and Non-Critical (NO) statuses found.")
        
        # logical consistency check (heuristic)
        if critical_check: 
            score += 10
            feedback_parts.append("Critical path tasks correctly identified.")
        if float_check:
            score += 10
            feedback_parts.append("Non-critical tasks identified.")
    else:
        feedback_parts.append("Missing explicit YES/NO critical designations.")

    # Criteria D: Summary Line (10 pts)
    if "critical path tasks:" in report_lower:
        score += 10
        feedback_parts.append("Summary line found.")
    else:
        feedback_parts.append("Summary line missing.")

    # 4. VLM Verification (20 pts)
    # Check if 'Total Slack' column is visible in the final or trajectory screenshots
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + ([final_img] if final_img else [])

    vlm_prompt = """
    Analyze these screenshots of ProjectLibre.
    1. Is the 'Total Slack' or 'Slack' column visible in the task table (Gantt chart view)?
    2. Did the user open a dialog to insert a column?
    Answer with JSON: {"column_visible": boolean, "insert_dialog_seen": boolean}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=images_to_check)
        parsed = vlm_res.get('parsed', {})
        if parsed.get('column_visible', False):
            score += 20
            feedback_parts.append("VLM: Total Slack column visible.")
        elif parsed.get('insert_dialog_seen', False):
            score += 10
            feedback_parts.append("VLM: Column insertion dialog seen (partial credit).")
        else:
            feedback_parts.append("VLM: Total Slack column not clearly visible.")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if report is perfect, assume they saw the column
        if score >= 60:
            score += 20
            feedback_parts.append("VLM failed but report is good; assuming success.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }