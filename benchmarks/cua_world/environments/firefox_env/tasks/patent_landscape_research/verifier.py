#!/usr/bin/env python3
"""
Verifier for patent_landscape_research task.

Criteria:
1. JSON Report Validity (structure, required fields) - 30 pts
2. Patent Data Quality (valid US formats, dates, keywords) - 40 pts
3. Firefox Evidence (History & Bookmarks) - 30 pts

Pass Threshold: 60/100
"""

import json
import re
import os
import tempfile
import logging
import datetime

logger = logging.getLogger(__name__)

def verify_patent_landscape_research(traj, env_info, task_info):
    """
    Verify the patent landscape research task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the Task Result Metadata (Browser state)
    task_result = {}
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # 2. Retrieve the User's Report
    report_data = {}
    report_valid_json = False
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/home/ga/Documents/patent_landscape.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
            report_valid_json = True
    except Exception as e:
        logger.warning(f"Could not load/parse patent_landscape.json: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    score = 0
    feedback = []

    # --- Criterion 1: Browser Evidence (30 pts) ---
    
    # History check (15 pts)
    google_visits = task_result.get("history_google_patents", 0)
    uspto_visits = task_result.get("history_uspto", 0)
    
    if google_visits > 0 or uspto_visits > 0:
        score += 15
        feedback.append(f"Browser history confirms research (Google: {google_visits}, USPTO: {uspto_visits}).")
    else:
        feedback.append("No relevant browser history found.")

    # Bookmark check (15 pts)
    folder_exists = task_result.get("bookmark_folder_exists", False)
    bm_count = task_result.get("bookmark_count_in_folder", 0)
    
    if folder_exists:
        if bm_count >= 5:
            score += 15
            feedback.append(f"Bookmark folder exists with {bm_count} items (+15).")
        elif bm_count >= 1:
            score += 10
            feedback.append(f"Bookmark folder exists but only has {bm_count} items (target 5) (+10).")
        else:
            score += 5
            feedback.append("Bookmark folder exists but is empty (+5).")
    else:
        feedback.append("Required bookmark folder 'Patent Landscape Research' not found.")

    # --- Criterion 2: JSON Structure & Basic Requirements (30 pts) ---
    
    if not report_valid_json:
        feedback.append("Report file is missing or invalid JSON.")
    else:
        # Check freshness
        if task_result.get("report_fresh", False):
            score += 10
            feedback.append("Report file created during task (+10).")
        else:
            feedback.append("Report file timestamp is old or invalid.")

        # Check keys
        required_keys = ["patents", "key_assignees", "summary"]
        missing_keys = [k for k in required_keys if k not in report_data]
        
        if not missing_keys:
            score += 10
            feedback.append("Report has correct top-level structure (+10).")
        else:
            feedback.append(f"Report missing keys: {missing_keys}.")

        # Check patent list size
        patents = report_data.get("patents", [])
        if isinstance(patents, list) and len(patents) >= 5:
            score += 10
            feedback.append(f"Report contains {len(patents)} patents (+10).")
        elif isinstance(patents, list) and len(patents) > 0:
            score += 5
            feedback.append(f"Report contains only {len(patents)} patents (target 5) (+5).")
        else:
            feedback.append("Patents list is empty or invalid.")

    # --- Criterion 3: Data Quality (40 pts) ---
    
    if report_valid_json and isinstance(report_data.get("patents"), list):
        patents = report_data["patents"]
        
        valid_patents_count = 0
        valid_dates_count = 0
        relevant_titles_count = 0
        
        # Regex for US patent number (e.g., US7952322B2, US11000000, US2020...)
        # Broad regex to catch utility patents
        pat_regex = re.compile(r"^US\d{6,11}[A-Za-z]\d?$")
        
        keywords = ["wireless", "power", "charging", "inductive", "magnetic", "coupling", "transfer", "receiver", "transmitter"]

        for p in patents:
            p_num = str(p.get("patent_number", "")).strip().upper()
            p_date = str(p.get("grant_date", "")).strip()
            p_title = str(p.get("title", "")).lower()

            # Check ID format
            if pat_regex.match(p_num):
                valid_patents_count += 1
            
            # Check date format YYYY-MM-DD
            try:
                datetime.datetime.strptime(p_date, "%Y-%m-%d")
                valid_dates_count += 1
            except ValueError:
                pass
            
            # Check relevance
            if any(k in p_title for k in keywords):
                relevant_titles_count += 1

        # Score calculations
        # ID Format (15 pts)
        if valid_patents_count >= 5:
            score += 15
            feedback.append("Patent IDs are valid US format (+15).")
        elif valid_patents_count > 0:
            score += 5
            feedback.append(f"Some Patent IDs valid ({valid_patents_count}) (+5).")
            
        # Dates (10 pts)
        if valid_dates_count >= 5:
            score += 10
            feedback.append("Grant dates are in valid format (+10).")
            
        # Relevance (15 pts)
        if relevant_titles_count >= 3:
            score += 15
            feedback.append("Patent titles are relevant to topic (+15).")
        elif relevant_titles_count > 0:
            score += 5
            feedback.append("Some patent titles relevant (+5).")
        else:
            feedback.append("Patent titles do not appear relevant to wireless power.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }