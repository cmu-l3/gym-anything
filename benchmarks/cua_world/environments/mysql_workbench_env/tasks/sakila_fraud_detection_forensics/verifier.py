#!/usr/bin/env python3
"""
Verifier for sakila_fraud_detection_forensics task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_fraud_detection_forensics(traj, env_info, task_info):
    """
    Verify the Sakila Fraud Detection task.
    
    Scoring:
    - View exists: 10 pts
    - View has correct columns: 10 pts
    - Detects Time Travel anomaly: 20 pts
    - Detects Nepotism anomaly: 20 pts
    - Detects Hoarding anomaly: 20 pts
    - Union Implementation (all types present): 10 pts (Implicit if all detected)
    - CSV Export exists and valid: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. View Existence (10 pts)
    if result.get("view_exists", 0) > 0:
        score += 10
        feedback.append("View v_fraud_report created (+10)")
    else:
        feedback.append("View v_fraud_report NOT found")
        
    # 2. Column Structure (10 pts)
    if result.get("view_has_columns", False):
        score += 10
        feedback.append("View structure correct (+10)")
    else:
        feedback.append("View missing required columns (fraud_type, incident_id)")

    # 3. Detection Logic (60 pts total)
    # Time Travel (20)
    if result.get("detected_time_travel", False):
        score += 20
        feedback.append("Time Travel anomaly detected (+20)")
    else:
        feedback.append("Failed to detect Time Travel anomaly")
        
    # Nepotism (20)
    if result.get("detected_nepotism", False):
        score += 20
        feedback.append("Nepotism anomaly detected (+20)")
    else:
        feedback.append("Failed to detect Nepotism anomaly")
        
    # Hoarding (20)
    if result.get("detected_hoarding", False):
        score += 20
        feedback.append("Hoarding anomaly detected (+20)")
    else:
        feedback.append("Failed to detect Hoarding anomaly")
        
    # 4. Union check (10 pts) - awarded if at least 2 types are detected implies union used
    detections = sum([
        result.get("detected_time_travel", False),
        result.get("detected_nepotism", False),
        result.get("detected_hoarding", False)
    ])
    if detections >= 2:
        score += 10
        feedback.append("Union logic verified (+10)")
    else:
        feedback.append("Union logic weak or single query used")

    # 5. CSV Export (10 pts)
    csv_exists = result.get("csv_exists", False)
    csv_rows = result.get("csv_rows", 0)
    csv_mtime = result.get("csv_mtime", 0)
    task_start = result.get("task_start_time", 0)
    
    if csv_exists and csv_rows >= 3 and csv_mtime > task_start:
        score += 10
        feedback.append("CSV export verified (+10)")
    elif csv_exists:
        feedback.append(f"CSV export found but empty or old (rows: {csv_rows})")
    else:
        feedback.append("CSV export NOT found")
        
    passed = score >= 60 and detections >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }