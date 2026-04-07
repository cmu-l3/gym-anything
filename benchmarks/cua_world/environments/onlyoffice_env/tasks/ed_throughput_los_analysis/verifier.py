#!/usr/bin/env python3
"""
Verifier for ED Throughput & LOS Analysis task.

Evaluates the agent's ability to process clinical timestamp data,
calculate performance metrics (Door-to-Doctor, LOS), flag target
breaches (LOS > 240 mins), and summarize by acuity level (ESI).

Verification Strategy:
1. Programmatic Checks (Spreadsheet content parsing via openpyxl)
   - Checks for presence of calculated text/metrics.
   - Validates that target breach flags and ESI summary numbers exist.
2. VLM Verification (Trajectory + Final Screenshot)
   - Verifies visual creation of dashboard, tables, and workflow progression.
"""

import sys
import os
import json
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_all_text(wb):
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 2000), max_col=min(sheet.max_column, 30)):
            for cell in row:
                if cell.value is not None:
                    all_text.append(str(cell.value).lower())
    return " ".join(all_text)

def extract_all_numbers(wb):
    numbers = []
    for sn in wb.sheetnames:
        sheet = wb[sn]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 2000), max_col=min(sheet.max_column, 30)):
            for cell in row:
                if isinstance(cell.value, (int, float)):
                    numbers.append(cell.value)
    return numbers

def verify_vlm(traj):
    """VLM verification checking if a dashboard/summary table was created."""
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_to_check = frames + [final] if final else frames
    
    if not images_to_check:
        return 0, "No trajectory images available for VLM check."
        
    prompt = """Analyze this sequence of screenshots from a spreadsheet application.
    The user is acting as a healthcare informatics analyst building an Emergency Department operations dashboard.
    
    Did the user successfully:
    1. Organize data and create new columns for calculated metrics (like LOS or Door-to-Doctor)?
    2. Create a summary section, pivot table, or distinct dashboard area summarizing data by ESI acuity level?
    
    Reply ONLY in valid JSON format:
    {"dashboard_created": true/false, "metrics_calculated": true/false, "confidence": "high/medium/low"}
    """
    
    try:
        response = query_vlm(images=images_to_check, prompt=prompt)
        parsed = response.get('parsed', {})
        if parsed.get('dashboard_created') and parsed.get('metrics_calculated'):
            return 25, "VLM confirmed dashboard creation and metric calculations."
        elif parsed.get('metrics_calculated') or parsed.get('dashboard_created'):
            return 12, "VLM confirmed partial dashboard/metric completion."
        else:
            return 0, "VLM did not observe dashboard creation."
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        return 0, f"VLM error: {str(e)}"

def verify_ed_throughput(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read exported metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = export_result.get('output_exists', False)
    file_created = export_result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Dashboard workbook not found."}
    
    if not file_created:
        # Anti-gaming check: File existed before task
        return {"passed": False, "score": 0, "feedback": "Workbook was not created or modified during the task."}

    # Extract workbook content
    container_path = "/home/ga/Documents/Spreadsheets/ed_operations_dashboard.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_ed_')
    
    score = 0
    feedback_parts = ["File verified modified during task (15/15)"]
    score += 15

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
        if not success:
            return {"passed": False, "score": score, "feedback": f"Failed to parse Excel file: {error}"}

        all_text = extract_all_text(wb)
        all_numbers = extract_all_numbers(wb)
        num_sheets = len(wb.sheetnames)

        # 1. Formatting & Sheets (10 pts)
        if num_sheets > 1:
            score += 10
            feedback_parts.append("Multiple sheets used (10/10)")
        else:
            feedback_parts.append("All work on single sheet (0/10)")

        # 2. LOS and Door-to-Doctor text evidence (15 pts)
        has_los = any(t in all_text for t in ["los", "length of stay", "total time"])
        has_d2d = any(t in all_text for t in ["door-to", "door to", "door to doc", "md seen delay", "wait time"])
        if has_los and has_d2d:
            score += 15
            feedback_parts.append("LOS and Door-to-Doctor labels present (15/15)")
        elif has_los or has_d2d:
            score += 7
            feedback_parts.append("Partial metric labels present (7/15)")

        # 3. Breach Flag Evidence (10 pts)
        has_breach_flag = any(t in all_text for t in ["breach", "compliant", "exceeded", "target met", "over 240", "violation"])
        has_target_num = 240 in all_numbers or 4 in all_numbers  # 240 mins or 4 hours
        if has_breach_flag and has_target_num:
            score += 10
            feedback_parts.append("Target breach flagging present (10/10)")
        elif has_breach_flag or has_target_num:
            score += 5
            feedback_parts.append("Partial target flagging present (5/10)")

        # 4. ESI & LWBS Summaries (25 pts)
        has_esi = sum(1 for t in ["esi", "acuity", "level"] if t in all_text) > 0
        has_lwbs = "lwbs" in all_text or "left without" in all_text
        
        # Check for percentages indicating rate calculations (~4% expected)
        has_percentages = any(0 < n < 10 for n in all_numbers if isinstance(n, float)) or \
                          any(str(n) + "%" in all_text for n in range(1, 10))
                          
        if has_esi and has_lwbs and has_percentages:
            score += 25
            feedback_parts.append("ESI and LWBS summaries present (25/25)")
        elif has_esi or has_lwbs:
            score += 12
            feedback_parts.append("Partial summaries present (12/25)")
            
    except Exception as e:
        logger.error(f"Error during programmatic check: {e}")
        feedback_parts.append(f"Parse error: {str(e)}")
    finally:
        cleanup_temp_dir(temp_dir)

    # 5. VLM Verification (25 pts)
    vlm_score, vlm_feedback = verify_vlm(traj)
    score += vlm_score
    feedback_parts.append(vlm_feedback)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }