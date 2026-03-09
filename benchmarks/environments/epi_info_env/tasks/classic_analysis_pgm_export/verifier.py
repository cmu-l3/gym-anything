#!/usr/bin/env python3
"""
Verifier for classic_analysis_pgm_export task.
"""

import json
import tempfile
import os
import logging
import csv
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classic_analysis_export(traj, env_info, task_info):
    """
    Verifies that the agent used Classic Analysis to filter data, create a derived variable,
    and export it to CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path')
    expected_column = metadata.get('expected_column', 'FoodCount')
    filter_column = metadata.get('filter_column', 'ILL')
    filter_value = metadata.get('filter_value', 'Yes')

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside container is C:\temp\task_result.json
        # Convert to appropriate path format if needed, but copy_from_env usually handles absolute paths
        copy_from_env("C:\\temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Verify Output File Existence & Timestamp (Anti-Gaming)
    # ================================================================
    if task_result.get('output_exists'):
        score += 15
        feedback_parts.append("Export file exists")
        
        if task_result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task session")
        else:
            feedback_parts.append("File timestamp indicates pre-existing file (anti-gaming fail)")
    else:
        feedback_parts.append("Export file NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 3. Inspect CSV Content
    # ================================================================
    csv_valid = False
    filter_correct = False
    variable_derived = False
    variable_values_valid = False
    
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_output_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            if rows:
                csv_valid = True
                score += 10 # CSV is parseable
                
                # Check Filter (ILL == Yes)
                # Note: CSV export might normalize booleans or strings. 
                # Oswego ILL is typically "Yes"/"No".
                non_ill_count = 0
                ill_count = 0
                for row in rows:
                    val = row.get(filter_column, '')
                    if val.lower() in ['yes', 'y', '1', 'true']:
                        ill_count += 1
                    else:
                        non_ill_count += 1
                
                if non_ill_count == 0 and ill_count > 0:
                    filter_correct = True
                    score += 20
                    feedback_parts.append(f"Filter correct ({ill_count} records)")
                elif ill_count == 0:
                    feedback_parts.append("File contains no ill records")
                else:
                    feedback_parts.append(f"Filter failed: Found {non_ill_count} non-ill records")

                # Check Row Count (approx 46 ill cases)
                if 40 <= ill_count <= 50:
                    score += 10
                    feedback_parts.append("Row count plausible")
                else:
                    feedback_parts.append(f"Unexpected row count: {ill_count}")

                # Check Derived Variable (FoodCount)
                # Column name matching (case-insensitive)
                headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
                target_header = expected_column.lower()
                
                if target_header in headers:
                    variable_derived = True
                    score += 15
                    feedback_parts.append(f"Variable '{expected_column}' found")
                    
                    # Verify values (integers 0-14)
                    valid_values = True
                    real_col_name = [h for h in reader.fieldnames if h.lower() == target_header][0]
                    
                    for row in rows:
                        try:
                            val = float(row[real_col_name])
                            if not (0 <= val <= 14):
                                valid_values = False
                                break
                        except ValueError:
                            valid_values = False
                            break
                    
                    if valid_values:
                        variable_values_valid = True
                        score += 10
                        feedback_parts.append("Derived variable values valid (0-14)")
                    else:
                        feedback_parts.append("Derived variable contains invalid values")
                else:
                    feedback_parts.append(f"Variable '{expected_column}' NOT found in headers")
                    
            else:
                feedback_parts.append("CSV file is empty")

    except Exception as e:
        feedback_parts.append(f"Failed to parse CSV: {str(e)}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # ================================================================
    # 4. VLM Verification (Trajectory)
    # ================================================================
    # We want to see the Program Editor or commands being typed.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying if a user performed a data analysis task in Epi Info 7.
    
    Look at the sequence of screenshots. The user should have:
    1. Opened the 'Classic Analysis' module.
    2. Written commands in the Program Editor window (text area).
    3. Commands should include: READ, DEFINE, ASSIGN, SELECT, WRITE/EXPORT.
    4. Run the commands (Analysis Output window showing results).
    
    Did the user write and run analysis commands?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        # Assuming VLM returns a boolean or text judgment we can parse
        # If the model is not returning JSON, we rely on a positive sentiment in text
        response_text = str(vlm_result.get("response", "")).lower()
        if "yes" in response_text and "command" in response_text:
            vlm_passed = True
            score += 20
            feedback_parts.append("VLM confirms commands were written/executed")
        else:
            feedback_parts.append("VLM did not observe clear command execution")
    else:
        feedback_parts.append("VLM check skipped/failed")

    # ================================================================
    # Final Scoring
    # ================================================================
    # Total possible: 15 (exist) + 10 (timestamp) + 10 (csv valid) + 20 (filter) + 10 (rows) + 15 (col exists) + 10 (vals) + 20 (vlm) = 110? 
    # Let's cap at 100.
    
    # Adjusted weights:
    # Exist: 15
    # Timestamp: 10
    # CSV Valid: 10
    # Filter Correct: 20
    # Row Count: 10
    # Col Exists: 15
    # Vals Valid: 10
    # VLM: 10
    # Total: 100
    
    # Recalculate VLM score to 10
    if vlm_passed:
        score -= 10 # adjusting from 20 down to 10 effectively
    
    # Pass threshold
    passed = score >= 60 and filter_correct and variable_derived
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }