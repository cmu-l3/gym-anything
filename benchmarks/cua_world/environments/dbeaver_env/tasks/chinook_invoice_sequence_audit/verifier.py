#!/usr/bin/env python3
"""
Verifier for chinook_invoice_sequence_audit task.
"""

import json
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_invoice_sequence_audit(traj, env_info, task_info):
    """
    Verifies the gap analysis task.
    
    Scoring Criteria:
    1. DBeaver Connection 'ChinookAudit' exists (10 pts)
    2. CSV file exists and created during task (10 pts)
    3. CSV Header is correct (10 pts)
    4. Gap Detection Accuracy (50 pts) - Matches ground truth gaps
    5. MissingCount Accuracy (10 pts)
    6. SQL Script exists (10 pts)
    """
    
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

    # 1. Connection Check (10 pts)
    if result.get("connection_found"):
        score += 10
        feedback.append("✓ 'ChinookAudit' connection found.")
    else:
        feedback.append("✗ 'ChinookAudit' connection not found in DBeaver configuration.")

    # 2. CSV Existence & Timestamp (10 pts)
    csv_exists = result.get("csv_exists")
    created_during = result.get("file_created_during_task")
    
    if csv_exists and created_during:
        score += 10
        feedback.append("✓ Output CSV created during task.")
    elif csv_exists:
        score += 5
        feedback.append("⚠ Output CSV exists but timestamp is old (pre-existing?).")
    else:
        feedback.append("✗ Output CSV not found.")

    # 3. CSV Header Check (10 pts)
    # Expected: GapStartId, GapEndId, MissingCount (case insensitive, order loose)
    expected_cols = {"gapstartid", "gapendid", "missingcount"}
    header_line = result.get("csv_header", "").lower()
    
    # Simple parse
    try:
        # Handle quoted headers if present
        reader = csv.reader(io.StringIO(header_line))
        headers = next(reader)
        headers_lower = [h.strip().lower() for h in headers]
        
        # Check if all expected columns are present
        missing_cols = [col for col in expected_cols if col not in headers_lower]
        
        if not missing_cols:
            score += 10
            feedback.append("✓ CSV header is correct.")
        else:
            feedback.append(f"✗ CSV header missing columns: {', '.join(missing_cols)}.")
    except Exception:
        feedback.append("✗ Could not parse CSV header.")

    # 4. Gap Accuracy (50 pts) & 5. Count Accuracy (10 pts)
    ground_truth = result.get("ground_truth", {}).get("gaps", [])
    csv_content = result.get("csv_content_sample", "")
    
    detected_gaps = []
    try:
        # Parse the sample content
        # We assume the header was line 1, so we parse the full content string
        f = io.StringIO(csv_content)
        reader = csv.DictReader(f)
        
        # Normalize column names to lowercase for robust matching
        reader.fieldnames = [name.lower() for name in reader.fieldnames]
        
        for row in reader:
            try:
                # Map various casing to standard keys
                start = int(row.get("gapstartid", row.get("start", -1)))
                end = int(row.get("gapendid", row.get("end", -1)))
                count = int(row.get("missingcount", row.get("count", -1)))
                detected_gaps.append({"start": start, "end": end, "count": count})
            except ValueError:
                continue
                
    except Exception as e:
        feedback.append(f"⚠ Error parsing CSV data rows: {e}")

    # Compare detected vs ground truth
    # Ground Truth: 10-10(1), 25-26(2), 50-50(1), 100-104(5)
    matched_gaps = 0
    correct_counts = 0
    
    for gt in ground_truth:
        found = False
        for det in detected_gaps:
            if det["start"] == gt["start"] and det["end"] == gt["end"]:
                found = True
                matched_gaps += 1
                if det["count"] == gt["count"]:
                    correct_counts += 1
                break
        if not found:
            feedback.append(f"✗ Missed gap: IDs {gt['start']}-{gt['end']}")
    
    # Scoring Gaps (12.5 pts per gap, total 50)
    gap_score = (matched_gaps / len(ground_truth)) * 50 if ground_truth else 0
    score += gap_score
    if matched_gaps == len(ground_truth):
        feedback.append("✓ All gaps identified correctly.")
    
    # Scoring Counts (2.5 pts per correct count, total 10)
    count_score = (correct_counts / len(ground_truth)) * 10 if ground_truth else 0
    score += count_score
    
    # 6. SQL Script Existence (10 pts)
    if result.get("sql_exists"):
        score += 10
        feedback.append("✓ SQL script saved.")
    else:
        feedback.append("✗ SQL script not found.")

    # Final pass determination
    # Threshold 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }