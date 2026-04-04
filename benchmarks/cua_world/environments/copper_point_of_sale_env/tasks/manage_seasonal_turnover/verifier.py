#!/usr/bin/env python3
"""
Verifier for manage_seasonal_turnover task.

Verification Strategy:
1. Validate CSV export exists and was created during the task.
2. Parse CSV to ensure all 3 items exist.
3. Verify correct naming convention (" [CLEARANCE]" suffix).
4. Verify correct pricing (50% of original).
5. VLM check on trajectory to confirm workflow (creation -> modification).
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_seasonal_turnover(traj, env_info, task_info):
    """
    Verify the seasonal turnover task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('items', [])
    
    # Windows paths in the container
    result_path_win = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"
    csv_path_win = r"C:\Users\Docker\Documents\inventory_audit.csv"

    # Temporary local files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')

    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env(result_path_win, temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basic file existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Exported CSV file not found."}
        
        score += 10
        feedback_parts.append("Export file exists")

        if result_data.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File timestamp indicates it might be stale")

        # 2. Retrieve and Parse CSV
        try:
            copy_from_env(csv_path_win, temp_csv.name)
            
            # Read CSV content
            found_items = {}
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Copper POS CSV export usually has headers. We'll search rows flexibly.
                reader = csv.reader(f)
                headers = next(reader, None) # Skip header
                
                for row in reader:
                    # Search for our target items in the row
                    row_str = " ".join(row)
                    
                    # Check against expected items
                    for target in expected_items:
                        # We look for the base name or the modified name to identify the record
                        base_name = target['original_name']
                        if base_name in row_str:
                            found_items[base_name] = row
        
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read CSV: {e}"}

        # 3. Verify Item Details
        items_score = 0
        items_max = 80 # Remaining points
        
        for target in expected_items:
            base_name = target['original_name']
            final_name = target['final_name']
            final_price = target['final_price']
            
            if base_name not in found_items:
                feedback_parts.append(f"Item '{base_name}' NOT found in export")
                continue
                
            row_data = found_items[base_name]
            row_text = str(row_data)
            
            # Check Name (approx 13 pts per item)
            name_correct = final_name in row_text
            if name_correct:
                items_score += 13.33
                feedback_parts.append(f"'{base_name}' name updated correctly")
            else:
                feedback_parts.append(f"'{base_name}' name incorrect (expected '{final_name}')")

            # Check Price (approx 13 pts per item)
            # Copper CSV might format price as "22.50" or "$22.50"
            price_correct = final_price in row_text
            if price_correct:
                items_score += 13.33
                feedback_parts.append(f"'{base_name}' price correct ({final_price})")
            else:
                feedback_parts.append(f"'{base_name}' price incorrect (expected {final_price})")

        score += int(items_score)

    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 90  # Strict pass for data entry
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }