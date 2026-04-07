#!/usr/bin/env python3
"""
Verifier for Practice Activity Volume Analysis.
Compares agent's generated CSV against the ground truth generated during setup.
"""

import json
import csv
import io
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_practice_activity_volume_analysis(traj, env_info, task_info):
    """
    Verifies the CSV report of patient activity.
    
    Criteria:
    1. Output file exists and was created during task.
    2. Header matches 'Month,Count'.
    3. Data rows match ground truth exactly (strict check) or with high tolerance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    metadata = result.get("metadata", {})
    agent_content = result.get("agent_csv_content")
    gt_content = result.get("ground_truth_csv_content")

    score = 0
    feedback = []
    
    # 1. Check file existence (10 pts)
    if not metadata.get("output_exists") or agent_content is None:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    score += 10
    feedback.append("File created.")

    # 2. Check creation time (10 pts)
    if metadata.get("file_created_during_task"):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("File timestamp indicates it was not created during this task run.")

    # Parse CSVs
    try:
        agent_rows = list(csv.reader(io.StringIO(agent_content)))
        gt_rows = list(csv.reader(io.StringIO(gt_content))) if gt_content else []
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid CSV format: {str(e)}"}

    if not agent_rows:
        return {"passed": False, "score": score, "feedback": "CSV file is empty."}

    # 3. Check Header (10 pts)
    header = [h.strip().lower() for h in agent_rows[0]]
    expected_header = ['month', 'count']
    
    if header == expected_header:
        score += 10
        feedback.append("Header format correct.")
    else:
        feedback.append(f"Incorrect header. Expected 'Month,Count', got '{','.join(agent_rows[0])}'")

    # 4. Check Data Accuracy (70 pts)
    # Convert rows to dictionary { 'YYYY-MM': count } for comparison
    def parse_data(rows):
        data = {}
        for row in rows[1:]: # Skip header
            if len(row) < 2: continue
            try:
                # Normalize month format if needed (though task asks for YYYY-MM)
                key = row[0].strip()
                val = int(row[1])
                data[key] = val
            except ValueError:
                continue
        return data

    agent_data = parse_data(agent_rows)
    gt_data = parse_data(gt_rows)

    if not gt_data:
        # Should not happen if setup worked
        return {"passed": False, "score": score, "feedback": "System error: Ground truth missing."}

    matches = 0
    total_months = len(gt_data)
    
    # Strict comparison of counts per month
    errors = []
    for month, count in gt_data.items():
        agent_count = agent_data.get(month)
        if agent_count == count:
            matches += 1
        else:
            errors.append(f"{month}: expected {count}, got {agent_count}")

    # Calculate accuracy score
    # We assign points based on percentage of matching months
    if total_months > 0:
        accuracy = matches / total_months
        accuracy_points = int(70 * accuracy)
        score += accuracy_points
        
        if accuracy == 1.0:
            feedback.append("All data points match ground truth exactly.")
        else:
            feedback.append(f"Data accuracy: {matches}/{total_months} months matched.")
            if errors:
                feedback.append(f"Sample errors: {', '.join(errors[:3])}...")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }