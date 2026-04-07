#!/usr/bin/env python3
"""
Verifier for geographic_catchment_analysis task.
Compares the agent's CSV report against a ground truth CSV generated from the database.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_csv_data(csv_path):
    """Reads a CSV and returns a set of tuples (postal_code, age_bracket, sex, count) for easy comparison."""
    data = set()
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers by stripping whitespace
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
            
            for row in reader:
                # Extract and normalize values
                cp = str(row.get('postal_code', '')).strip()
                age = str(row.get('age_bracket', '')).strip()
                sex = str(row.get('sex', '')).strip()
                count = str(row.get('patient_count', '')).strip()
                
                if cp and age and sex and count:
                    data.add((cp, age, sex, count))
    except Exception as e:
        logger.error(f"Error reading CSV {csv_path}: {e}")
        return None
    return data

def verify_catchment_analysis(traj, env_info, task_info):
    """
    Verifies the epidemiological report task.
    
    Scoring:
    - File exists & created during task: 15 pts
    - Correct Headers: 10 pts
    - Data Accuracy: 75 pts (percentage of matching rows vs ground truth)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check basics
    if not res_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score = 0
    feedback = []

    # Score: File created during task (Anti-gaming)
    if res_data.get('file_created_during_task'):
        score += 15
        feedback.append("File created during task session.")
    else:
        feedback.append("WARNING: File timestamp is old (pre-task).")

    # Score: Headers
    if res_data.get('headers_match'):
        score += 10
        feedback.append("CSV headers are correct.")
    else:
        feedback.append("CSV headers mismatch.")

    # 2. Retrieve Agent CSV and Ground Truth CSV
    agent_csv_remote = res_data.get('agent_csv_path')
    truth_csv_remote = res_data.get('ground_truth_csv_path')
    
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(agent_csv_remote, temp_agent.name)
        copy_from_env(truth_csv_remote, temp_truth.name)
        
        agent_data = normalize_csv_data(temp_agent.name)
        truth_data = normalize_csv_data(temp_truth.name)
        
        if agent_data is None:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | Could not parse agent CSV."}
            
        if truth_data is None:
             return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | System error: Could not parse ground truth."}

        # Compare Data
        # We check intersection.
        # Max score for data is 75.
        
        total_truth_rows = len(truth_data)
        if total_truth_rows == 0:
             return {"passed": False, "score": 0, "feedback": "System error: Ground truth empty."}

        matching_rows = len(agent_data.intersection(truth_data))
        
        # Calculate accuracy
        accuracy = matching_rows / total_truth_rows
        data_points = int(accuracy * 75)
        score += data_points
        
        feedback.append(f"Data Accuracy: {matching_rows}/{total_truth_rows} rows matched ({int(accuracy*100)}%).")
        
        # Check for extra rows (hallucinations)
        extra_rows = len(agent_data) - matching_rows
        if extra_rows > 0:
            feedback.append(f"Note: {extra_rows} incorrect extra rows found.")
            # Optional penalty? Let's keep it simple for now, maybe subtract 1 point per extra row up to 5
            penalty = min(5, extra_rows)
            score = max(0, score - penalty)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error during file comparison: {e}"}
    finally:
        if os.path.exists(temp_agent.name): os.unlink(temp_agent.name)
        if os.path.exists(temp_truth.name): os.unlink(temp_truth.name)

    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }