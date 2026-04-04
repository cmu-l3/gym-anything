#!/usr/bin/env python3
"""
Verifier for Detect Survey Logic Errors Task.

Criteria:
1. Output file 'validation_errors.csv' exists (15 pts)
2. File was created during the task session (anti-gaming) (15 pts)
3. Correct logic: Caught 'GenderConflict' errors (IDs 15, 42, 78, 91) (25 pts)
4. Correct logic: Caught 'SkipConflict' errors (IDs 5, 33, 60) (25 pts)
5. Precision: No valid records falsely identified as errors (20 pts)

Uses 'copy_from_env' to retrieve the CSV produced by the agent.
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_survey_logic_errors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    metadata = task_info.get('metadata', {})
    expected_error_ids = set(metadata.get('error_ids', ["15", "42", "78", "91", "5", "33", "60"]))
    
    # Ground truth specific sets
    gender_conflict_ids = {"15", "42", "78", "91"}
    skip_conflict_ids = {"5", "33", "60"}

    score = 0
    max_score = 100
    feedback = []

    # Temporary file paths
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv_output = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    try:
        # 1. Retrieve Task Result JSON
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence and timestamp
        if task_result.get('output_exists'):
            score += 15
            feedback.append("Output file exists.")
        else:
            feedback.append("Output file 'validation_errors.csv' NOT found.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        if task_result.get('file_created_during_task'):
            score += 15
            feedback.append("File created during task session.")
        else:
            feedback.append("File timestamp indicates it was not created during this session.")

        # 2. Retrieve and Analyze the Output CSV
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\SurveyData\\validation_errors.csv", temp_csv_output)
            
            agent_found_ids = set()
            agent_rows = []
            
            with open(temp_csv_output, 'r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                # Normalize headers (remove extra spaces, lower case)
                headers = [h.strip().lower() for h in reader.fieldnames or []]
                
                if 'respondentid' not in headers:
                    return {"passed": False, "score": score, "feedback": "Output CSV missing 'RespondentID' column."}

                for row in reader:
                    # Robust ID extraction
                    # Find the actual key that matches 'respondentid' case-insensitively
                    id_key = next((k for k in row.keys() if k.strip().lower() == 'respondentid'), None)
                    if id_key and row[id_key]:
                        rid = row[id_key].strip()
                        agent_found_ids.add(rid)
                        agent_rows.append(row)

        except Exception as e:
            feedback.append(f"Error reading output CSV: {str(e)}")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # 3. Logic Verification
        
        # Calculate Recall
        true_positives = agent_found_ids.intersection(expected_error_ids)
        missing_errors = expected_error_ids - agent_found_ids
        
        # Split scores by error type
        found_gender = true_positives.intersection(gender_conflict_ids)
        found_skip = true_positives.intersection(skip_conflict_ids)
        
        # Score Gender Conflicts (25 pts)
        if len(gender_conflict_ids) > 0:
            gender_score = (len(found_gender) / len(gender_conflict_ids)) * 25
            score += gender_score
            if len(found_gender) == len(gender_conflict_ids):
                feedback.append("All Gender conflicts detected.")
            else:
                feedback.append(f"Detected {len(found_gender)}/{len(gender_conflict_ids)} Gender conflicts.")

        # Score Skip Conflicts (25 pts)
        if len(skip_conflict_ids) > 0:
            skip_score = (len(found_skip) / len(skip_conflict_ids)) * 25
            score += skip_score
            if len(found_skip) == len(skip_conflict_ids):
                feedback.append("All Skip Pattern conflicts detected.")
            else:
                feedback.append(f"Detected {len(found_skip)}/{len(skip_conflict_ids)} Skip Pattern conflicts.")

        # 4. Precision (False Positives) (20 pts)
        false_positives = agent_found_ids - expected_error_ids
        if len(false_positives) == 0:
            score += 20
            feedback.append("No false positives (Clean).")
        else:
            # Penalize proportional to false positives, but don't go negative on this section
            penalty = len(false_positives) * 5
            precision_score = max(0, 20 - penalty)
            score += precision_score
            feedback.append(f"Found {len(false_positives)} false positives (Records {', '.join(list(false_positives)[:3])}...).")

        passed = (score >= 80)

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"System error during verification: {e}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result_json):
            os.remove(temp_result_json)
        if os.path.exists(temp_csv_output):
            os.remove(temp_csv_output)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }