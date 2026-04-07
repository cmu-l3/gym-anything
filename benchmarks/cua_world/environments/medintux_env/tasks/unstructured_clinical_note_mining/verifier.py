#!/usr/bin/env python3
"""
Verifier for Unstructured Clinical Note Mining task.
Verifies that the agent correctly identified patients with penicillin mentions
in the free-text notes, handling case and accent variations.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_mining(traj, env_info, task_info):
    """
    Verify the CSV export of patients with penicillin allergies.
    
    Criteria:
    1. Output file exists and follows CSV format.
    2. Recall: Found all hidden positive cases (accented, uppercase, lowercase).
    3. Precision: Did not include negative cases.
    4. Process: File created during task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Load Task Result Metadata
    try:
        with tempfile.NamedTemporaryFile(suffix=".json") as f:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    if not result_meta.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += 10 # File exists
    
    if result_meta.get("created_during_task"):
        score += 10 # Created recently
    else:
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")

    # 2. Load Ground Truth
    ground_truth_ids = set()
    try:
        with tempfile.NamedTemporaryFile(mode='w+', suffix=".txt") as f:
            copy_from_env("/tmp/ground_truth_ids.txt", f.name)
            f.seek(0)
            for line in f:
                guid = line.strip()
                if guid:
                    ground_truth_ids.add(guid)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        # If we can't load ground truth, we can't verify content.
        return {"passed": False, "score": score, "feedback": "Verification error: Ground truth missing."}

    # 3. Analyze Agent Output
    agent_ids = set()
    try:
        with tempfile.NamedTemporaryFile(mode='w+', suffix=".csv") as f:
            copy_from_env("/tmp/agent_output.csv", f.name)
            f.seek(0)
            
            # Simple CSV sniffing
            try:
                reader = csv.reader(f)
                header = next(reader, None) # Skip header
                
                # Check if file has data
                has_data = False
                for row in reader:
                    if not row: continue
                    has_data = True
                    # Assume GUID is first column (standard practice or as requested)
                    # Or try to find GUID-like string in row
                    found_guid = None
                    for col in row:
                        if len(col) > 20 and '-' in col: # GUID heuristic
                            found_guid = col.strip()
                            break
                        # Fallback: exact match with known GUIDs
                        if col.strip() in ground_truth_ids:
                            found_guid = col.strip()
                            break
                    
                    if found_guid:
                        agent_ids.add(found_guid)
                    elif len(row) > 0:
                        # If we can't find a GUID, maybe they exported just names?
                        # This is harder to verify. We'll strict fail if no GUID-like data found
                        # unless the task description allowed flexibility.
                        # Task asked for "PatientGUID" column.
                        # Try first column if it looks alphanumeric
                        if len(row[0]) > 5:
                            agent_ids.add(row[0].strip())
                            
                if not has_data:
                     feedback.append("CSV file appears empty.")
            except csv.Error:
                 feedback.append("File is not valid CSV.")

    except Exception as e:
        feedback.append(f"Failed to read output CSV: {e}")

    # 4. Scoring Logic
    true_positives = agent_ids.intersection(ground_truth_ids)
    false_positives = agent_ids.difference(ground_truth_ids)
    missed = ground_truth_ids.difference(agent_ids)
    
    recall_count = len(true_positives)
    total_expected = len(ground_truth_ids)
    
    # Score Calculation
    if total_expected > 0:
        # 50 points for Recall
        recall_score = (recall_count / total_expected) * 50
        score += recall_score
        
        if recall_count == total_expected:
            feedback.append("Perfect Recall: Found all target patients.")
        elif recall_count > 0:
            feedback.append(f"Partial Recall: Found {recall_count}/{total_expected} patients.")
        else:
            feedback.append("No correct patients found.")
    
    # 30 points for Precision (avoiding false positives)
    if len(agent_ids) > 0:
        precision = len(true_positives) / len(agent_ids)
        precision_score = precision * 30
        score += precision_score
        
        if len(false_positives) > 0:
            feedback.append(f"Precision Warning: Included {len(false_positives)} incorrect patients.")
    else:
        # If file empty or no IDs found, 0 precision points
        pass

    # Final tally
    passed = (score >= 70) and (recall_count > 0)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback),
        "details": {
            "found": list(true_positives),
            "missed": list(missed),
            "extra": list(false_positives)
        }
    }