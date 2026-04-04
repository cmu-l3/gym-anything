#!/usr/bin/env python3
"""
Verifier for URI Structure Hygiene Audit task.

Verification Logic:
1. CSV Verification (50 pts):
   - File exists and created during task
   - Contains crawler-test.com URLs (anti-gaming)
   - Sufficient row count (shows actual crawl)
   - Contains 'Address' column (shows it's a URL export)

2. Report Verification (40 pts):
   - File exists and created during task
   - Minimum length (non-empty)
   - Contains required keywords (analysis happened)
   - Contains numeric values (counts/lengths)
   
3. Process Verification (10 pts):
   - Screaming Frog running or used

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging
import csv
import re

logger = logging.getLogger(__name__)

def verify_uri_structure_hygiene_audit(traj, env_info, task_info):
    """Verify the URI hygiene audit task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load JSON result
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_json.close()
        copy_from_env('/tmp/task_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    min_csv_rows = metadata.get('min_csv_rows', 20)
    min_report_chars = metadata.get('min_report_chars', 400)
    report_keywords = metadata.get('report_keywords', ["length", "uppercase", "underscore"])

    # --- Criterion 1: CSV Export (50 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_valid_time = result.get('csv_created_during_task', False)
    csv_rows = result.get('csv_row_count', 0)
    csv_domain = result.get('csv_has_target_domain', False)
    
    csv_score = 0
    if csv_exists and csv_valid_time:
        # Check CSV content details by loading the copied file
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            temp_csv.close()
            copy_from_env('/tmp/verify_uri_export.csv', temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                f.seek(0)
                reader = csv.reader(f)
                headers = next(reader, [])
                
                # Check 1: Domain verification (Critical)
                if "crawler-test.com" in content:
                    csv_score += 15
                    feedback_parts.append("CSV contains target domain")
                else:
                    feedback_parts.append("CSV missing target domain")

                # Check 2: Row count
                if csv_rows >= min_csv_rows:
                    csv_score += 15
                    feedback_parts.append(f"CSV row count ok ({csv_rows})")
                elif csv_rows > 0:
                    csv_score += 5
                    feedback_parts.append(f"CSV row count low ({csv_rows})")

                # Check 3: Headers (Address column)
                headers_lower = [h.lower() for h in headers]
                if any("address" in h for h in headers_lower) or any("url" in h for h in headers_lower):
                    csv_score += 20
                    feedback_parts.append("CSV structure valid (Address column)")
                else:
                    feedback_parts.append("CSV missing Address/URL column")
            
            os.unlink(temp_csv.name)
            
        except Exception as e:
            feedback_parts.append(f"Error verifying CSV content: {e}")
    else:
        feedback_parts.append("CSV not found or not created during task")
    
    score += csv_score

    # --- Criterion 2: Report Content (40 pts) ---
    report_exists = result.get('report_exists', False)
    report_valid_time = result.get('report_created_during_task', False)
    report_size = result.get('report_size', 0)
    
    report_score = 0
    if report_exists and report_valid_time:
        try:
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_report.close()
            copy_from_env('/tmp/verify_report.txt', temp_report.name)
            
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                text = f.read().lower()
            
            # Check 1: Length
            if report_size >= min_report_chars:
                report_score += 10
                feedback_parts.append(f"Report length ok ({report_size} chars)")
            elif report_size > 100:
                report_score += 5
                feedback_parts.append("Report too short")
            else:
                feedback_parts.append("Report empty/trivial")

            # Check 2: Keywords
            found_kw = [kw for kw in report_keywords if kw in text]
            if len(found_kw) >= 3:
                report_score += 15
                feedback_parts.append(f"Keywords found: {len(found_kw)}")
            elif len(found_kw) > 0:
                report_score += 5
                feedback_parts.append("Few keywords found")

            # Check 3: Numeric Values (Must contain analysis counts)
            # Look for digits
            numbers = re.findall(r'\d+', text)
            if len(numbers) >= 3:
                report_score += 15
                feedback_parts.append("Report contains numeric analysis")
            else:
                feedback_parts.append("Report missing numeric counts")
                
            os.unlink(temp_report.name)
            
        except Exception as e:
            feedback_parts.append(f"Error verifying report content: {e}")
    else:
        feedback_parts.append("Report not found or not created during task")

    score += report_score

    # --- Criterion 3: Process (10 pts) ---
    sf_running = result.get('sf_running', False)
    if sf_running or score > 0: # If they produced output, they must have run it
        score += 10
        feedback_parts.append("Process verified")
    else:
        feedback_parts.append("Screaming Frog not running")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "csv_score": csv_score,
            "report_score": report_score,
            "total_score": score
        }
    }