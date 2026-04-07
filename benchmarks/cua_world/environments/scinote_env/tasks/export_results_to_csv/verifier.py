#!/usr/bin/env python3
"""Verifier for export_results_to_csv task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_results(traj, env_info, task_info):
    """
    Verify that the user extracted the experimental data and saved it locally.
    
    Robust check handles standard commas, tabs (from copy-pasting handsontable UI), 
    and checks actual scientific data values to ensure successful data extraction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported file metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/export_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = result_meta.get('file_exists', False)
    created_during_task = result_meta.get('file_created_during_task', False)

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target CSV file (kinetics_data.csv) was not found in ~/Documents/."
        }

    # 2. Load the actual CSV file content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/kinetics_data.csv", temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but failed to read content: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    score = 20
    feedback_parts = ["CSV file exists"]

    # Criterion A: Timing check to prevent static file gaming
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during task window")

    # 3. Parse content (handle standard comma CSV or tab-separated copy-paste from UI)
    delimiter = '\t' if '\t' in content else ','
    raw_rows = [line.split(delimiter) for line in content.strip().split('\n') if line.strip()]

    # Clean the rows (removing empty whitespace cells)
    cleaned_rows = []
    for row in raw_rows:
        cr = [cell.strip() for cell in row if cell.strip()]
        if cr:
            cleaned_rows.append(cr)

    if not cleaned_rows:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | CSV is empty/invalid"}

    # Criterion B: Header Validation
    headers = [h.lower() for h in cleaned_rows[0]]
    has_time = any("time" in h for h in headers)
    has_abs = any("absorbance" in h or "abs" in h for h in headers)

    if has_time and has_abs:
        score += 20
        feedback_parts.append("Expected headers found")
    else:
        feedback_parts.append(f"Headers missing expected terms (found: {headers})")

    # Criterion C: Row Validation
    data_rows = cleaned_rows[1:]
    if len(data_rows) >= 6:
        score += 20
        feedback_parts.append("Found expected number of data rows (6)")
    else:
        feedback_parts.append(f"Row count mismatch (found {len(data_rows)} data rows, expected 6)")

    # Criterion D: Ground Truth Data Extraction Accuracy
    found_10 = False
    found_60 = False
    
    for row in data_rows:
        if len(row) >= 2:
            if row[0] == "10" and "0.45" in row[1]:
                found_10 = True
            if row[0] == "60" and "0.95" in row[1]:
                found_60 = True

    if found_10 and found_60:
        score += 30
        feedback_parts.append("Data values match ELN ground truth perfectly")
    elif found_10 or found_60:
        score += 15
        feedback_parts.append("Data values partially match ELN ground truth")
    else:
        feedback_parts.append("Data values do not match ELN ground truth")

    # Overall Evaluation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }