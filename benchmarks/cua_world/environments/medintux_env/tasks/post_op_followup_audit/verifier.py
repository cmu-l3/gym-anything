#!/usr/bin/env python3
"""
Verifier for post_op_followup_audit task.
"""

import json
import base64
import os
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_post_op_audit(traj, env_info, task_info):
    """
    Verify the patient audit CSV report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = "temp_task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", temp_file)
        with open(temp_file, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file):
            os.remove(temp_file)

    # Basic checks
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}

    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task window."}

    # Decode Content
    try:
        csv_content = base64.b64decode(result.get("csv_content_b64", "")).decode('utf-8')
        ground_truth = json.loads(base64.b64decode(result.get("ground_truth_b64", "")).decode('utf-8'))
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to decode content: {str(e)}"}

    # Parse CSV
    reported_guids = set()
    rows = []
    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        # Normalize headers (remove BOM, strip whitespace, lower case)
        reader.fieldnames = [h.strip().lower() for h in reader.fieldnames] if reader.fieldnames else []
        
        if 'guid' not in reader.fieldnames:
             return {"passed": False, "score": 20, "feedback": "CSV is missing 'GUID' column."}

        for row in reader:
            rows.append(row)
            guid = row.get('guid', '').strip()
            if guid:
                reported_guids.add(guid)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Invalid CSV format: {str(e)}"}

    # Scoring Logic
    score = 20 # Base points for valid file
    feedback = ["File created and readable."]

    # Ground Truth Sets
    expected_guids = set(p['guid'] for p in ground_truth['non_compliant'])
    compliant_guids = set(p['guid'] for p in ground_truth['compliant'])

    # Calculate Metrics
    true_positives = reported_guids.intersection(expected_guids)
    false_positives = reported_guids.intersection(compliant_guids)
    missed_positives = expected_guids - reported_guids

    # 1. Identify Non-Compliant Patients (30 pts)
    # 10 pts per correct identification (3 expected)
    tp_score = len(true_positives) * 10
    score += tp_score
    if len(true_positives) == len(expected_guids):
        feedback.append("Correctly identified all non-compliant patients.")
    else:
        feedback.append(f"Identified {len(true_positives)}/{len(expected_guids)} non-compliant patients.")

    # 2. Exclude Compliant Patients (30 pts)
    # Start with 30, deduct 10 for each false positive
    fp_penalty = len(false_positives) * 10
    exclusion_score = max(0, 30 - fp_penalty)
    score += exclusion_score
    
    if len(false_positives) > 0:
        feedback.append(f"Incorrectly included {len(false_positives)} compliant patients (False Positives).")
    else:
        feedback.append("Correctly excluded all compliant patients.")

    # 3. Handling Logic Boundary Cases (20 pts)
    # Check specifically for the tricky cases
    # Case F (LEROY - Day 8 - Non-Compliant) -> Must be in list
    leroy_guid = next((p['guid'] for p in ground_truth['non_compliant'] if p['nom'] == 'LEROY'), None)
    if leroy_guid and leroy_guid in reported_guids:
        score += 10
        feedback.append("Correctly handled Day 8 boundary (Non-Compliant).")
    
    # Case D (BERNARD - Day 7 - Compliant) -> Must NOT be in list
    bernard_guid = next((p['guid'] for p in ground_truth['compliant'] if p['nom'] == 'BERNARD'), None)
    if bernard_guid and bernard_guid not in reported_guids:
        score += 10
        feedback.append("Correctly handled Day 7 boundary (Compliant).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }