#!/usr/bin/env python3
"""
Verifier for customize_columns_and_export_csv task.
Checks if the exported CSV has the correct columns, data types, and specific content.
"""

import json
import os
import csv
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_columns(traj, env_info, task_info):
    """
    Verify the CSV export for correct columns and formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence
    if not result_data.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file http_activity_log.csv not found."
        }

    # Retrieve the actual CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(result_data["output_path"], temp_csv.name)
        
        # Parse CSV
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Wireshark CSVs usually have headers
            reader = csv.reader(f)
            headers = next(reader, None)
            rows = list(reader)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 10, 
            "feedback": f"Output file exists but could not be parsed as CSV: {e}"
        }
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    score = 0
    feedback_parts = []

    # 1. File Created During Task (Anti-gaming) - 10 pts
    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task.")

    # 2. Column Count Check - 15 pts
    # We expect 6 columns: Time, Source, Dest, Host, Method, URI
    # Wireshark exports "No." by default if not removed, so count matters.
    if headers:
        clean_headers = [h.strip().replace('"', '') for h in headers if h.strip()]
        if len(clean_headers) == 6:
            score += 15
            feedback_parts.append("Correct number of columns (6).")
        else:
            feedback_parts.append(f"Incorrect column count: found {len(clean_headers)}, expected 6.")
            # If they kept defaults, they might have 7 or more
            if len(clean_headers) > 6:
                feedback_parts.append("Did you remove the default columns (No., Protocol, etc.)?")

    # 3. Header Name Verification - 15 pts
    expected_headers = ["Time", "Source", "Destination", "Host", "Method", "URI"]
    header_matches = 0
    if headers:
        # Fuzzy match headers
        header_str = " ".join(clean_headers).lower()
        for exp in expected_headers:
            if exp.lower() in header_str:
                header_matches += 1
        
        if header_matches >= 5:
            score += 15
            feedback_parts.append("Column headers match requirements.")
        else:
            feedback_parts.append(f"Column headers mismatch. Found: {clean_headers}")

    # 4. Time Format Verification - 20 pts
    # Should be Absolute/UTC (contains date/time components), NOT relative (just float)
    time_format_correct = False
    if rows and len(rows) > 0:
        first_time = rows[0][0] # Assuming first col is Time
        # Regex for date-like string (e.g., "2004-05-13" or "May 13, 2004")
        if re.search(r'[-/:]', first_time) and len(first_time) > 10:
            time_format_correct = True
            score += 20
            feedback_parts.append("Time format appears to be Absolute/UTC.")
        else:
            feedback_parts.append(f"Time format looks incorrect (expected absolute date/time): '{first_time}'")
    
    # 5. Content Verification (Host/Method/URI) - 40 pts
    # We look for specific known values from http.cap
    # Packet 4 is usually the first GET request to www.ethereal.com
    content_found = {
        "host": False,
        "method": False,
        "uri": False
    }
    
    # Scan first 10 rows for expected data
    for row in rows[:10]:
        row_str = " ".join(row)
        if "www.ethereal.com" in row_str:
            content_found["host"] = True
        if "GET" in row_str:
            content_found["method"] = True
        if "/download.html" in row_str:
            content_found["uri"] = True
            
    if content_found["host"]: score += 15
    else: feedback_parts.append("Column 'Host' data not found (expected 'www.ethereal.com').")
    
    if content_found["method"]: score += 15
    else: feedback_parts.append("Column 'Method' data not found (expected 'GET').")
    
    if content_found["uri"]: score += 10
    else: feedback_parts.append("Column 'URI' data not found (expected '/download.html').")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }