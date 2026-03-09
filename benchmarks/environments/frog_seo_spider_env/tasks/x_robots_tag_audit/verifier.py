#!/usr/bin/env python3
"""
Verifier for X-Robots-Tag Audit task.
"""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_x_robots_tag_audit(traj, env_info, task_info):
    """
    Verify the X-Robots-Tag audit task.
    
    Criteria:
    1. Screaming Frog running (10 pts)
    2. Correct CSV file created during task (20 pts)
    3. CSV contains 'X-Robots-Tag' column (20 pts)
    4. CSV contains expected test URLs (e.g. /headers/x_robots_tag_noindex) (30 pts)
    5. CSV has non-empty values in X-Robots-Tag column (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []

    # 1. SF Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running")
    else:
        feedback_parts.append("Screaming Frog NOT running")

    # 2. File Created (20 pts)
    if result.get('file_exists', False) and result.get('file_created_during_task', False):
        score += 20
        feedback_parts.append("CSV exported correctly")
    elif result.get('file_exists', False):
        score += 5
        feedback_parts.append("CSV exists but timestamp invalid")
    else:
        feedback_parts.append("CSV file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Analyze CSV Content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/x_robots_export_copy.csv", temp_csv.name)
        
        has_x_col = False
        has_target_urls = False
        has_values = False
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames or []
            
            # Find the X-Robots-Tag column (could be "X-Robots-Tag", "X-Robots-Tag 1", etc.)
            x_robot_cols = [h for h in headers if "x-robots-tag" in h.lower()]
            if x_robot_cols:
                has_x_col = True
                
            # Check rows
            for row in reader:
                # Check for target URL
                address = row.get('Address', '') or row.get('URL', '')
                if '/headers/x_robots_tag_' in address:
                    has_target_urls = True
                
                # Check for values in X-Robots-Tag column
                for col in x_robot_cols:
                    if row.get(col, '').strip():
                        has_values = True

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Column check (20 pts)
    if has_x_col:
        score += 20
        feedback_parts.append("X-Robots-Tag column found")
    else:
        feedback_parts.append("X-Robots-Tag column MISSING")

    # 4. Target URLs check (30 pts)
    if has_target_urls:
        score += 30
        feedback_parts.append("Target URLs found")
    else:
        feedback_parts.append("Target X-Robots-Tag URLs missing")

    # 5. Values check (20 pts)
    if has_values:
        score += 20
        feedback_parts.append("Data values present")
    else:
        feedback_parts.append("X-Robots-Tag column is empty")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }