#!/usr/bin/env python3
"""
Verifier for query_and_export_chemical_subset task.

Verifies that the agent:
1. Created the CSV output file.
2. Filtered the data correctly (only Chlorine records).
3. Included the correct columns.
"""

import json
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_and_export(traj, env_info, task_info):
    """
    Verify the CSV export for the chemical query task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    positive_matches = metadata.get('positive_matches', [])
    negative_matches = metadata.get('negative_matches', [])
    required_columns = metadata.get('required_columns', [])

    # Load result JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, paths are different, but copy_from_env handles the container path
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Score breakdown
    score = 0
    feedback = []
    
    # 1. File Existence & Timing (20 pts)
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += 10
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("WARNING: File timestamp check failed (modified before task start).")

    # 2. Parse CSV Content
    content = result.get('file_content', '')
    if not content or content == "ERROR_READING_FILE":
        return {"passed": False, "score": score, "feedback": "File is empty or unreadable."}

    try:
        # Handle potential BOM or encoding issues by stripped
        f = io.StringIO(content.strip())
        reader = csv.DictReader(f)
        rows = list(reader)
        headers = reader.fieldnames if reader.fieldnames else []
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}

    # 3. Check Headers (20 pts)
    # Loose matching for headers (case-insensitive, partial)
    missing_cols = []
    headers_lower = [h.lower() for h in headers]
    
    for req in required_columns:
        found = False
        for h in headers_lower:
            if req.lower() in h:
                found = True
                break
        if not found:
            missing_cols.append(req)
            
    if not missing_cols:
        score += 20
        feedback.append("All required columns present.")
    else:
        feedback.append(f"Missing columns: {', '.join(missing_cols)}")
        # Partial credit
        if len(missing_cols) < len(required_columns):
            score += 10

    # 4. Check Data Filtering (40 pts)
    # Check Positive Matches (Should exist)
    found_positives = 0
    for pos in positive_matches:
        match = False
        for row in rows:
            # Check all values in row
            if any(pos.lower() in str(val).lower() for val in row.values()):
                match = True
                break
        if match:
            found_positives += 1
    
    if found_positives == len(positive_matches):
        score += 20
        feedback.append(f"Found all {len(positive_matches)} expected Chlorine facilities.")
    elif found_positives > 0:
        score += 10
        feedback.append(f"Found {found_positives}/{len(positive_matches)} expected facilities.")
    else:
        feedback.append("Did not find expected Chlorine facilities.")

    # Check Negative Matches (Should NOT exist) - Anti-Gaming
    found_negatives = 0
    for neg in negative_matches:
        match = False
        for row in rows:
            if any(neg.lower() in str(val).lower() for val in row.values()):
                match = True
                break
        if match:
            found_negatives += 1
            
    if found_negatives == 0:
        score += 20
        feedback.append("Correctly filtered out non-Chlorine facilities.")
    else:
        feedback.append(f"FAILED: Export included {found_negatives} unrelated facilities (did you export all records?).")
        # Heavy penalty for not filtering
        score -= 10

    # 5. Check 'Maximum Daily Amount' data (20 pts)
    # Verify the column actually has data, not just empty
    has_amount_data = False
    for row in rows:
        # Find the column that corresponds to amount
        for k, v in row.items():
            if "amount" in k.lower() or "quantity" in k.lower() or "code" in k.lower():
                if v and str(v).strip():
                    has_amount_data = True
                    break
        if has_amount_data:
            break
            
    if has_amount_data:
        score += 20
        feedback.append("Export includes quantity data.")
    else:
        feedback.append("Quantity data column appears empty.")

    # Final Check
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }