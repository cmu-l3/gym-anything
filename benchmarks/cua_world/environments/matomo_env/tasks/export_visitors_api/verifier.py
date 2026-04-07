#!/usr/bin/env python3
"""
Verifier for Export Visitors API task in Matomo.

Verification Strategy:
1. Check if CSV file exists at expected path.
2. Check if file was created during the task window (anti-gaming).
3. Verify file content structure (CSV headers).
4. Verify key metrics are present (visits, actions, etc.).
5. Verify sufficient data points (rows) to ensure correct date range was used.

Scoring (100 points):
- File exists: 15 pts
- Created during task: 10 pts
- Non-trivial size (>100 bytes): 10 pts
- Valid CSV headers (not HTML error): 25 pts
- Contains correct metrics: 25 pts
- Sufficient rows (>5): 15 pts

Pass threshold: 60 points
"""

import sys
import os
import json
import logging
import tempfile
import base64
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_visitors_api(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the visitors summary CSV was exported correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_columns', ["nb_visits", "nb_actions"])
    
    try:
        # Copy result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. File Existence (15 pts)
    if result.get('file_exists', False):
        score += 15
        feedback_parts.append("File exists")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file not found at /home/ga/Documents/matomo_visitors_export.csv"
        }

    # 2. Anti-gaming / Timestamp (10 pts)
    if result.get('created_during_task', False):
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("File timestamp predates task start (anti-gaming check failed)")

    # 3. File Size (10 pts)
    size = result.get('file_size', 0)
    if size > 100:
        score += 10
        feedback_parts.append(f"Valid file size ({size} bytes)")
    else:
        feedback_parts.append(f"File too small/empty ({size} bytes)")

    # Decode content for analysis
    content_sample = ""
    try:
        if result.get('content_sample_base64'):
            content_sample = base64.b64decode(result.get('content_sample_base64')).decode('utf-8', errors='ignore')
    except Exception:
        pass

    header_line = result.get('header_line', "")
    
    # 4. Valid CSV Headers (25 pts)
    # Check if it looks like a CSV (comma separated) and not HTML (<!DOCTYPE html>)
    if "<!DOCTYPE" in content_sample or "<html" in content_sample:
        feedback_parts.append("File appears to be an HTML error page, not CSV")
    elif "," in header_line or "\t" in header_line:
        score += 25
        feedback_parts.append("Valid CSV format detected")
        
        # 5. Content Metrics (25 pts)
        # Check for expected Matomo metric column names
        found_metrics = 0
        missing_metrics = []
        for metric in expected_columns:
            if metric in header_line:
                found_metrics += 1
            else:
                missing_metrics.append(metric)
        
        if found_metrics >= 2: # At least some matches
            score += 25
            feedback_parts.append(f"Found {found_metrics} expected metric columns")
        else:
            feedback_parts.append(f"Missing key metrics: {', '.join(missing_metrics)}")
            
    else:
        feedback_parts.append("Invalid file format (headers not recognized)")

    # 6. Sufficient Rows (15 pts)
    # If period=day & date=last30, we expect ~31 lines (header + 30 days)
    # If period=range, we might get fewer, but usually still a summary
    line_count = result.get('line_count', 0)
    if line_count >= 5:
        score += 15
        feedback_parts.append(f"Sufficient data rows ({line_count})")
    else:
        feedback_parts.append(f"Insufficient data rows ({line_count}) - expected daily data")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }