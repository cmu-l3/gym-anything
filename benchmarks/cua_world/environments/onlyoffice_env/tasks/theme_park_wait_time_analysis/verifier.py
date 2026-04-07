#!/usr/bin/env python3
"""
Verifier for Theme Park Queue Operations Analysis task.

Evaluates the agent's ability to:
1. Process a large raw CSV dataset into a new sheet.
2. Add a calculated column bridging the gap between posted and actual waits, handling blanks.
3. Generate a Ride Summary comparing all 5 attractions.
4. Generate an Hourly Profile finding the peak congestion hour.
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import copy_and_parse_document

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_value_for_label(sheet, target_label):
    """Scan a sheet for a text label and return the first numeric value in the same row."""
    target_label = target_label.lower()
    for row in sheet.iter_rows(values_only=True):
        row_list = list(row)
        for i, cell in enumerate(row_list):
            if isinstance(cell, str) and target_label in cell.lower():
                # Search rightwards for any numeric value
                for val in row_list[i+1:]:
                    if isinstance(val, (int, float)):
                        return val
    return None

def verify_wait_time_analysis(traj, env_info, task_info):
    """
    Score the wait time analysis workbook.
    Total: 100 points. Pass threshold: 60.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # 1. Retrieve the exported JSON metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/theme_park_wait_time_analysis_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load export JSON: {e}")
        result_meta = {"output_file_exists": False}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve the task start timestamp for anti-gaming
    temp_ts = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    start_ts = 0
    try:
        copy_from_env("/tmp/theme_park_wait_time_analysis_start_ts", temp_ts.name)
        with open(temp_ts.name, 'r') as f:
            start_ts = int(f.read().strip())
    except:
        pass
    finally:
        if os.path.exists(temp_ts.name):
            os.unlink(temp_ts.name)

    if not result_meta.get("output_file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file theme_park_queue_analysis.xlsx was not found."
        }
    
    file_mtime = result_meta.get("output_mtime", 0)
    if start_ts > 0 and file_mtime < start_ts:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming failure: Target file was not modified during the task."
        }

    # 3. Load and parse the workbook
    container_path = "/home/ga/Documents/Spreadsheets/theme_park_queue_analysis.xlsx"
    success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse workbook: {error}"}

    score = 0
    feedback = []

    sheet_names_lower = [sn.lower() for sn in wb.sheetnames]

    # --- Criterion 1: Raw Data Sheet & Content (20 pts) ---
    raw_sheet = None
    for sn in wb.sheetnames:
        if "raw" in sn.lower() or "data" in sn.lower():
            raw_sheet = wb[sn]
            break

    if raw_sheet:
        row_count = raw_sheet.max_row
        if row_count > 1000:
            score += 20
            feedback.append("Raw Data sheet populated.")
        elif row_count > 100:
            score += 10
            feedback.append("Raw Data sheet partially populated.")
        else:
            feedback.append("Raw Data sheet lacks sufficient rows.")
    else:
        feedback.append("Raw Data sheet not found.")

    # --- Criterion 2: Discrepancy Calculation (15 pts) ---
    discrepancy_found = False
    if raw_sheet:
        # Check header row for 'discrep'
        headers = [str(c).lower() for c in next(raw_sheet.iter_rows(min_row=1, max_row=1, values_only=True)) if c]
        if any("discrep" in h or "diff" in h for h in headers):
            discrepancy_found = True
            score += 15
            feedback.append("Wait Discrepancy column created.")
        else:
            feedback.append("Wait Discrepancy column not identified in headers.")
    else:
        feedback.append("Skipping Discrepancy check due to missing Raw sheet.")

    # --- Criterion 3: Ride Summary Sheet (35 pts) ---
    ride_sheet = None
    for sn in wb.sheetnames:
        if "ride" in sn.lower() or "summary" in sn.lower():
            if sn != raw_sheet.title: # Don't re-use raw data sheet
                ride_sheet = wb[sn]
                break
    
    if ride_sheet:
        ride_summary_score = 0
        # Look for specific ride names and numeric values adjacent to them
        sdmt_val = find_value_for_label(ride_sheet, "seven dwarfs")
        sm_val = find_value_for_label(ride_sheet, "space mountain")
        
        if sdmt_val is not None:
            ride_summary_score += 15
        if sm_val is not None:
            ride_summary_score += 15
            
        if ride_summary_score > 0:
            score += ride_summary_score + 5  # Bonus 5 for creating the sheet properly
            feedback.append("Ride Summary sheet populated with ride aggregations.")
        else:
            score += 5
            feedback.append("Ride Summary sheet exists but aggregations missing.")
    else:
        feedback.append("Ride Summary sheet not found.")

    # --- Criterion 4: Hourly Profile Sheet (30 pts) ---
    hourly_sheet = None
    for sn in wb.sheetnames:
        if "hour" in sn.lower() or "profile" in sn.lower():
            if not ride_sheet or sn != ride_sheet.title:
                hourly_sheet = wb[sn]
                break

    if hourly_sheet:
        hourly_score = 0
        # Look for hour labels like '14', '15' or '2 PM', '3 PM'
        h14_val = find_value_for_label(hourly_sheet, "14") or find_value_for_label(hourly_sheet, "2 pm")
        h9_val = find_value_for_label(hourly_sheet, "9") or find_value_for_label(hourly_sheet, "9 am")
        
        if h14_val is not None or h9_val is not None:
            hourly_score += 25
            
        if hourly_score > 0:
            score += hourly_score + 5
            feedback.append("Hourly Profile sheet populated with aggregations.")
        else:
            score += 5
            feedback.append("Hourly Profile sheet exists but aggregations missing.")
    else:
        feedback.append("Hourly Profile sheet not found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }