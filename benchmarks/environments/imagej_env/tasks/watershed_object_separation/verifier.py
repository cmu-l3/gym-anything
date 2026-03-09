#!/usr/bin/env python3
"""
Verifier for watershed_object_separation task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_watershed_separation(traj, env_info, task_info):
    """
    Verify watershed segmentation task.

    Scoring (100 pts):
    - CSV created & valid timestamps (15 pts)
    - Summary txt created & valid timestamps (10 pts)
    - CSV contains valid measurements (>40 rows, valid areas) (35 pts)
    - Summary reports Before/After counts in valid ranges (20 pts)
    - Watershed proven: After count > Before count (15 pts)
    - Consistency: Summary After count ≈ CSV rows (5 pts)

    Pass threshold: 60 points AND Watershed proven
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_before_min = metadata.get('expected_before_min', 15)
    expected_before_max = metadata.get('expected_before_max', 50)
    expected_after_min = metadata.get('expected_after_min', 40)
    expected_after_max = metadata.get('expected_after_max', 85)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        
        # 1. File Existence & Timestamps (25 pts)
        task_start = result.get('task_start_time', 0)
        csv_exists = result.get('csv_exists', False)
        txt_exists = result.get('txt_exists', False)
        
        # CSV Check
        if csv_exists:
            if result.get('csv_modified_time', 0) > task_start:
                score += 15
                feedback_parts.append("Measurement CSV created")
            else:
                feedback_parts.append("CSV predates task start")
        else:
            feedback_parts.append("Measurement CSV missing")

        # TXT Check
        if txt_exists:
            if result.get('txt_modified_time', 0) > task_start:
                score += 10
                feedback_parts.append("Summary text created")
            else:
                feedback_parts.append("Summary text predates task")
        else:
            feedback_parts.append("Summary text missing")

        # 2. Measurement Data Quality (35 pts)
        row_count = result.get('csv_row_count', 0)
        valid_areas = result.get('valid_area_count', 0)
        
        if row_count >= expected_after_min:
            score += 20
            feedback_parts.append(f"Sufficient objects measured ({row_count})")
        elif row_count > 0:
            score += 10
            feedback_parts.append(f"Some objects measured ({row_count}), expected >{expected_after_min}")
        else:
            feedback_parts.append("No objects in CSV")

        if valid_areas > 0 and valid_areas >= row_count * 0.8:
            score += 15
            feedback_parts.append("Valid area measurements found")
        
        # 3. Summary Counts Logic (35 pts total)
        before = result.get('summary_before_count', -1)
        after = result.get('summary_after_count', -1)
        
        counts_valid = True
        
        # Check ranges
        if expected_before_min <= before <= expected_before_max:
            score += 10
            feedback_parts.append(f"Before count valid ({before})")
        elif before != -1:
            feedback_parts.append(f"Before count out of range ({before})")
            counts_valid = False
        else:
            feedback_parts.append("Before count not found")
            counts_valid = False

        if expected_after_min <= after <= expected_after_max:
            score += 10
            feedback_parts.append(f"After count valid ({after})")
        elif after != -1:
            feedback_parts.append(f"After count out of range ({after})")
            counts_valid = False
        else:
            feedback_parts.append("After count not found")
            counts_valid = False
            
        # CRITICAL: Watershed Logic (After > Before)
        watershed_proven = False
        if counts_valid and after > before:
            score += 15
            watershed_proven = True
            feedback_parts.append("Watershed separation confirmed (After > Before)")
        elif counts_valid:
            feedback_parts.append("FAIL: After count not greater than Before count")

        # 4. Consistency (5 pts)
        # The reported 'after' count should match the CSV rows roughly
        if counts_valid and abs(after - row_count) <= 5:
            score += 5
            feedback_parts.append("Counts consistent across files")
        
        # Determine Success
        passed = (score >= 60) and watershed_proven
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}