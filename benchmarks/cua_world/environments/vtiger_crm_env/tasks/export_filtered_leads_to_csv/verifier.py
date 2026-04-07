#!/usr/bin/env python3
"""
Verifier for export_filtered_leads_to_csv task.

Verifies:
1. Target file exists at expected path.
2. Target file was modified/created AFTER the task started (anti-gaming).
3. File is a valid CSV with Vtiger's standard export headers.
4. CSV contains exactly 18 data rows.
5. All data rows contain "Healthcare" in the Industry column.
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_filtered_leads(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/healthcare_leads.csv')
    expected_count = metadata.get('expected_record_count', 18)
    expected_industry = metadata.get('expected_industry', 'Healthcare')

    score = 0
    feedback_parts = []

    # 1. Read the export_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/export_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: File Existence
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": f"Target CSV file not found at {expected_path}"}
    
    score += 20
    feedback_parts.append("File exists")

    # Criterion 2: Timestamp verification (Anti-gaming)
    task_start = result.get('task_start_time', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File appears older than task start (possible gaming)")

    # 3. Read the actual CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.reader(f)
            rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + f" | Failed to parse CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if not rows or len(rows) < 1:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | CSV is empty"}

    headers = rows[0]
    data_rows = rows[1:]

    score += 10
    feedback_parts.append("Valid CSV format")

    # Criterion 3: Authentic Vtiger Export Headers
    header_lower = [h.strip().lower() for h in headers]
    if 'lead no' in header_lower and 'industry' in header_lower:
        score += 20
        feedback_parts.append("Authentic Vtiger export headers")
    else:
        feedback_parts.append("Headers do not match standard Vtiger export")

    # Criterion 4: Exact Record Count
    if len(data_rows) == expected_count:
        score += 20
        feedback_parts.append(f"Correct record count ({expected_count})")
    else:
        feedback_parts.append(f"Incorrect record count: {len(data_rows)} (expected {expected_count})")

    # Criterion 5: Perfect Filtering
    if 'industry' in header_lower:
        ind_idx = header_lower.index('industry')
        correct_industry_count = sum(1 for row in data_rows if len(row) > ind_idx and row[ind_idx].strip() == expected_industry)

        if len(data_rows) > 0 and correct_industry_count == len(data_rows):
            score += 20
            feedback_parts.append("Perfect filtering (All rows match expected Industry)")
        else:
            feedback_parts.append(f"Filtering error: {correct_industry_count}/{len(data_rows)} rows match expected Industry")
    else:
        feedback_parts.append("Cannot verify filtering: Industry column missing from CSV")

    # Determine pass/fail based on critical logic: must have correct count, correct filtering, and file exists.
    passed = (score >= 80) and (len(data_rows) == expected_count) and (file_mtime > task_start)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }