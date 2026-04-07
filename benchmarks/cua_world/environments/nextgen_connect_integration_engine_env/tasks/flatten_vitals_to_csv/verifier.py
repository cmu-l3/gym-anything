#!/usr/bin/env python3
"""
Verifier for flatten_vitals_to_csv task.

Criteria:
1. Channel created and listening on port 6661 (20 pts)
2. Output file created (10 pts)
3. Correct CSV structure and data extraction (70 pts)
   - 3 test cases sent
   - Case 1: Full vitals (25 pts)
   - Case 2: Sparse vitals (missing BP) (25 pts)
   - Case 3: Mixed order (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flatten_vitals_to_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    test_results = result.get("test_results", {})
    listening = test_results.get("listening", False)
    file_exists = test_results.get("file_exists", False)
    correct_lines = test_results.get("correct_lines", 0)
    messages_sent = test_results.get("messages_sent", 0)
    content_feedback = test_results.get("content_feedback", [])

    score = 0
    feedback_parts = []

    # Criterion 1: Channel Listener (20 pts)
    if listening:
        score += 20
        feedback_parts.append("Channel is listening on port 6661.")
    else:
        feedback_parts.append("FAIL: Channel is not listening on port 6661.")

    # Criterion 2: Output File Exists (10 pts)
    if file_exists:
        score += 10
        feedback_parts.append("Output file created.")
    else:
        feedback_parts.append("FAIL: Output file /tmp/research_data/vitals.csv not found.")

    # Criterion 3: Data Integrity (70 pts)
    # Scaled based on how many test cases passed
    # We sent 3 messages.
    if messages_sent > 0:
        # Calculate points per correct line
        points_per_line = 70 / 3
        data_score = int(correct_lines * points_per_line)
        score += data_score
        
        if correct_lines == 3:
            feedback_parts.append("All test cases passed (Full data, Sparse data, Mixed order).")
        else:
            feedback_parts.append(f"FAIL: Only {correct_lines}/3 test cases passed.")
            if content_feedback:
                feedback_parts.append("Details: " + "; ".join(content_feedback[:3]))
    else:
        feedback_parts.append("FAIL: No messages could be sent to channel.")

    # VLM Verification (Optional backup, usually strictly programmatic here is better, 
    # but we can add a small check if score is borderline, though purely functional is preferred for data tasks)
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }