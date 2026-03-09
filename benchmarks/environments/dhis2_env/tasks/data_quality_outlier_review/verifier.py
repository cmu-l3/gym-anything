#!/usr/bin/env python3
"""
Verifier for data_quality_outlier_review task.

Scoring (100 points total):
1. [25 pts] At least 1 new follow-up value marked in DB (MANDATORY).
2. [15 pts] At least 3 new follow-up values marked (Full Goal).
3. [20 pts] Export file found in Downloads (created during task).
4. [15 pts] Summary report file exists.
5. [10 pts] Summary report has substantive content (>200 chars).
6. [15 pts] Summary report contains keywords (e.g., district name, "outlier").

Pass Threshold: 60 points
Mandatory Condition: At least 1 follow-up marked.
"""

import json
import os
import sys
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_data_quality_outlier_review(traj, env_info, task_info):
    """
    Verifies that the agent performed outlier detection, flagged values,
    exported results, and wrote a report.
    """
    
    # 1. Setup: Retrieve result data from the environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data from agent environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    initial_cnt = int(result.get("initial_followup_count", 0))
    current_cnt = int(result.get("current_followup_count", 0))
    newly_updated = int(result.get("newly_updated_followups", 0))
    
    # Net increase in count is a strong signal if no update timestamp available
    net_increase = max(0, current_cnt - initial_cnt)
    
    # Use the larger of the two signals (net increase vs timestamp check) to be generous
    # Timestamp check is more precise, but net increase is a good fallback for the demo DB
    evidenced_flags = max(net_increase, newly_updated)

    export_found = result.get("export_file_found", False)
    report_exists = result.get("report_exists", False)
    report_len = int(result.get("report_length", 0))
    report_content = result.get("report_content_preview", "").lower()

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Follow-ups marked (MANDATORY)
    if evidenced_flags >= 1:
        score += 25
        feedback.append(f"✓ {evidenced_flags} value(s) flagged for follow-up (25/25 pts)")
    else:
        feedback.append("✗ No values flagged for follow-up (0/25 pts)")
        return {
            "passed": False,
            "score": score,
            "feedback": "FAILED: You must identify outlier values and mark them for follow-up by clicking the star icon in the Data Quality app. " + " | ".join(feedback)
        }

    # Criterion 2: Quantity of flags
    if evidenced_flags >= 3:
        score += 15
        feedback.append("✓ At least 3 values flagged (15/15 pts)")
    else:
        feedback.append(f"✗ Only {evidenced_flags}/3 required values flagged (0/15 pts)")

    # Criterion 3: Export file
    if export_found:
        score += 20
        feedback.append("✓ Results exported to Downloads (20/20 pts)")
    else:
        feedback.append("✗ No export file found in Downloads (0/20 pts)")

    # Criterion 4: Report exists
    if report_exists:
        score += 15
        feedback.append("✓ Report file created on Desktop (15/15 pts)")
    else:
        feedback.append("✗ Report file not found on Desktop (0/15 pts)")

    # Criterion 5 & 6: Report Content
    if report_exists:
        # Check substance
        if report_len > 200:
            score += 10
            feedback.append("✓ Report has substantive content (10/10 pts)")
        else:
            feedback.append("✗ Report is too short (<200 chars) (0/10 pts)")
        
        # Check specific keywords
        keywords = ["kailahun", "outlier", "deviation", "z-score", "standard", "facility"]
        found_keywords = [k for k in keywords if k in report_content]
        if len(found_keywords) >= 2:
            score += 15
            feedback.append(f"✓ Report mentions key terms ({', '.join(found_keywords[:3])}...) (15/15 pts)")
        else:
            feedback.append("✗ Report missing specific details (e.g., 'Kailahun', 'outlier') (0/15 pts)")
    else:
        feedback.append("✗ Report content checks skipped (file missing)")

    # 4. Final Result
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }