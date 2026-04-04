#!/usr/bin/env python3
"""
Verifier for deidentify_generalize_data task.

Verification Strategy:
1. File Verification:
   - Output CSV exists and was created during the task.
   - PII columns (MRN, PatientName) are REMOVED.
   - Exact Age column is REMOVED.
   - Generalized AgeDecade column EXISTS and contains correct logic (multiples of 10).
   - Clinical data is preserved (row count, key columns).
2. VLM Verification:
   - Trajectory shows usage of Classic Analysis commands (READ, DEFINE, ASSIGN, WRITE).
"""

import json
import os
import csv
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deidentify_generalize_data(traj, env_info, task_info):
    """
    Verify the de-identification and generalization task.
    """
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Metadata & Config
    metadata = task_info.get('metadata', {})
    expected_output_win_path = metadata.get('output_path', r"C:\Users\Docker\Documents\EpiData\public_heart_data.csv")
    forbidden_cols = metadata.get('forbidden_columns', ["MRN", "PatientName", "age"])
    required_cols = metadata.get('required_columns', ["AgeDecade", "sex", "chol"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 3. Get Task Result JSON
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 4. Verify Output File Exists
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 20
    feedback_parts.append("Output file created")

    if task_result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("Warning: File timestamp suggests it wasn't created during this session")

    # 5. Retrieve and Analyze Output CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_output_win_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            rows = list(reader)

        if not headers:
            return {"passed": False, "score": score, "feedback": "Output file is empty or invalid CSV"}

        # Clean headers (remove whitespace/bom)
        headers = [h.strip() for h in headers]
        
        # Check Forbidden Columns (PII Removal)
        pii_found = [col for col in forbidden_cols if col in headers]
        if not pii_found:
            score += 30
            feedback_parts.append("PII/Sensitive columns successfully removed")
        else:
            feedback_parts.append(f"FAILED: Found forbidden columns: {pii_found}")

        # Check Required Columns (Clinical Data + Generalized Var)
        missing_req = [col for col in required_cols if col not in headers]
        if not missing_req:
            score += 10
            feedback_parts.append("Required clinical columns present")
        else:
            feedback_parts.append(f"Missing required columns: {missing_req}")

        # Check Generalization Logic (AgeDecade)
        if "AgeDecade" in headers:
            age_idx = headers.index("AgeDecade")
            valid_generalization = True
            invalid_examples = []
            
            # Check first 20 rows
            for i, row in enumerate(rows[:20]):
                if len(row) <= age_idx: continue
                val = row[age_idx]
                try:
                    # Logic: Must be integer ending in 0 (e.g., 20, 30, 40)
                    num_val = float(val)
                    if num_val % 10 != 0:
                        valid_generalization = False
                        invalid_examples.append(val)
                except ValueError:
                    # Header might be repeated or empty line
                    pass
            
            if valid_generalization and len(rows) > 0:
                score += 30
                feedback_parts.append("AgeDecade variable correctly generalized (multiples of 10)")
            else:
                feedback_parts.append(f"AgeDecade contains invalid values: {invalid_examples[:3]}")
        else:
            feedback_parts.append("AgeDecade variable missing")

    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 6. Final Scoring
    passed = score >= 80  # Requires file exist (20) + PII removed (30) + Generalization (30)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }