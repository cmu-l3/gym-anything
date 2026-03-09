#!/usr/bin/env python3
"""
Verifier for dashboard_filter_export task.
Verifies that the agent correctly filtered the dataset and exported the result.
"""

import json
import os
import csv
import tempfile
import logging
from io import StringIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard_filter_export(traj, env_info, task_info):
    """
    Verify the Epi Info Dashboard task.
    Criteria:
    1. CSV output file exists and was created during task.
    2. CSV content contains exactly the subset of data: Vanilla=Yes AND Ill=No.
    3. Workspace file (.cvs7) exists (indicates usage of tool logic).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Get the Result JSON from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check CSV Existence and Timing (20 pts)
    csv_exists = result_data.get('csv_exists', False)
    csv_created = result_data.get('csv_created_during_task', False)
    csv_path = result_data.get('csv_path', '')

    if csv_exists and csv_created:
        score += 20
        feedback.append("CSV file created successfully.")
    elif csv_exists:
        score += 10
        feedback.append("CSV file exists but timestamp check failed (possibly created before task?).")
    else:
        feedback.append("CSV output file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 3. Verify CSV Content (60 pts)
    # We need to copy the CSV out to verify its content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        
        # Parse CSV
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            row_count = len(rows)
            
            # Ground Truth: 18 rows expected
            # Allow slight tolerance if header handling differs
            if 17 <= row_count <= 19:
                score += 30
                feedback.append(f"Row count correct ({row_count}).")
            else:
                feedback.append(f"Row count incorrect. Expected ~18, got {row_count}.")
            
            # Check Logic: Vanilla=Yes (or true/1) AND Ill=No (or false/0)
            correct_logic_count = 0
            for row in rows:
                # Normalize keys (case insensitive)
                row_lower = {k.lower(): v for k, v in row.items()}
                
                # Check Vanilla
                vanilla_val = row_lower.get('vanilla', '').lower()
                ill_val = row_lower.get('ill', '').lower()
                
                is_vanilla = vanilla_val in ['yes', 'y', 'true', '1']
                is_healthy = ill_val in ['no', 'n', 'false', '0']
                
                if is_vanilla and is_healthy:
                    correct_logic_count += 1
            
            if row_count > 0:
                accuracy = correct_logic_count / row_count
                if accuracy > 0.95:
                    score += 30
                    feedback.append("Data logic validated (Vanilla=Yes, Ill=No).")
                else:
                    feedback.append(f"Data logic check failed. Only {correct_logic_count}/{row_count} rows match criteria.")
            else:
                feedback.append("CSV is empty.")

    except Exception as e:
        feedback.append(f"Failed to verify CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Check Workspace (20 pts)
    workspace_exists = result_data.get('workspace_exists', False)
    if workspace_exists:
        score += 20
        feedback.append("Dashboard workspace saved.")
    else:
        feedback.append("Dashboard workspace file not found.")

    # Final Verification
    passed = score >= 80  # Requires CSV existence + correct data content
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }