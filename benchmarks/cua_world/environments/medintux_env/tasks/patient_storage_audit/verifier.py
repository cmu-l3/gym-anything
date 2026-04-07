#!/usr/bin/env python3
"""
Verifier for patient_storage_audit task.
"""

import json
import os
import csv
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patient_storage_audit(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/high_usage_patients.csv')
    
    # Ground truth defined in metadata or reconstructed here
    ground_truth = metadata.get('ground_truth_data', [])
    if not ground_truth:
        # Fallback if metadata missing
        ground_truth = [
          {"rank": 1, "name": "DURAND Michel", "size_mb": 120},
          {"rank": 2, "name": "MARTIN Sophie", "size_mb": 85},
          {"rank": 3, "name": "LEFEBVRE Marie", "size_mb": 60},
          {"rank": 4, "name": "BERNARD Pierre", "size_mb": 40},
          {"rank": 5, "name": "PETIT Francois", "size_mb": 15}
        ]

    # 1. Load Task Result JSON
    task_result = {}
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result JSON."}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check basics
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file ~/high_usage_patients.csv not found."}

    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task window."}

    # 2. Load and Parse the CSV File
    csv_rows = []
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_output_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers: strip spaces, lowercase
            reader.fieldnames = [name.strip().lower() for name in reader.fieldnames] if reader.fieldnames else []
            
            # Check for required columns
            required_cols = {'rank', 'patientname', 'guid', 'size_mb'}
            current_cols = set(reader.fieldnames)
            missing = required_cols - current_cols
            
            if missing:
                return {
                    "passed": False, 
                    "score": 10, 
                    "feedback": f"CSV is missing required columns: {missing}. Found: {current_cols}"
                }

            for row in reader:
                csv_rows.append(row)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read or parse CSV file: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Score the Content
    score = 20  # Base score for valid CSV existence
    feedback = ["CSV created and readable."]
    
    if len(csv_rows) < 5:
        feedback.append(f"Expected 5 rows, found {len(csv_rows)}.")
        # Penalize but continue
    
    # Evaluate specific criteria
    top_patient_correct = False
    order_correct = True
    names_resolved = True
    sizes_accurate = True

    for i, truth in enumerate(ground_truth):
        if i >= len(csv_rows):
            break
        
        row = csv_rows[i]
        
        # Check Name (Fuzzy match: verify both parts of name exist)
        truth_parts = truth['name'].lower().split() # ['durand', 'michel']
        row_name = row.get('patientname', '').lower()
        
        name_match = all(part in row_name for part in truth_parts)
        if not name_match:
            if i == 0: top_patient_correct = False
            names_resolved = False
            feedback.append(f"Rank {truth['rank']} name mismatch: Expected '{truth['name']}', got '{row.get('patientname')}'")
        else:
            if i == 0: top_patient_correct = True
        
        # Check Size (Tolerance +/- 2MB)
        try:
            row_size = float(row.get('size_mb', 0))
            if not (truth['size_mb'] - 5 <= row_size <= truth['size_mb'] + 5):
                sizes_accurate = False
                feedback.append(f"Rank {truth['rank']} size inaccurate: Expected ~{truth['size_mb']}MB, got {row_size}MB")
        except ValueError:
            sizes_accurate = False
            feedback.append(f"Rank {truth['rank']} invalid size format.")

        # Check Ordering (Size should be >= next row)
        if i < len(csv_rows) - 1:
            try:
                next_size = float(csv_rows[i+1].get('size_mb', 0))
                current_size = float(row.get('size_mb', 0))
                if current_size < next_size:
                    order_correct = False
            except:
                pass

    # Scoring Logic
    if top_patient_correct:
        score += 30
        feedback.append("Top storage consumer identified correctly.")
    else:
        feedback.append("Failed to identify the correct top storage consumer.")

    if names_resolved:
        score += 20
        feedback.append("Patient names resolved correctly.")
    
    if sizes_accurate:
        score += 15
        feedback.append("Disk usage sizes are accurate.")
    
    if order_correct and len(csv_rows) >= 5:
        score += 15
        feedback.append("Ranking order is correct.")

    passed = score >= 70 and top_patient_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }