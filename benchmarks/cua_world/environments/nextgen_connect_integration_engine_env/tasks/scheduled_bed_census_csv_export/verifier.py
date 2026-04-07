#!/usr/bin/env python3
"""
Verifier for Scheduled Bed Census CSV Reporter task.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scheduled_bed_census_csv_export(traj, env_info, task_info):
    """
    Verifies that the agent created a channel that reads from DB and writes a correct CSV.
    
    Scoring Criteria:
    1. Channel created & deployed (Database Reader -> File Writer)
    2. Output file exists and was created during task
    3. CSV Header is correct
    4. Data calculations (Occupancy %) are correct
    5. Logic (Status CRITICAL/NORMAL) is correct
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_data', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Load Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)
            
    # 2. Verify Channel Configuration (25 points)
    if task_result.get('channel_found'):
        score += 5
        feedback_parts.append("Channel 'Bed_Census_Reporter' found.")
        
        status = task_result.get('channel_status', 'UNKNOWN')
        if status in ['STARTED', 'DEPLOYED', 'RUNNING']:
            score += 10
            feedback_parts.append(f"Channel is {status}.")
        else:
            feedback_parts.append(f"Channel state is {status} (expected STARTED).")
            
        src_type = task_result.get('source_type', '')
        dst_type = task_result.get('destination_type', '')
        
        if 'Database Reader' in src_type:
            score += 5
        else:
            feedback_parts.append(f"Source is {src_type} (expected Database Reader).")
            
        if 'File Writer' in dst_type:
            score += 5
        else:
            feedback_parts.append(f"Destination is {dst_type} (expected File Writer).")
    else:
        feedback_parts.append("Channel 'Bed_Census_Reporter' not found.")
        
    # 3. Verify File Existence (15 points)
    if task_result.get('file_exists') and task_result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("Output CSV file created.")
        
        # 4. Verify CSV Content (60 points)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
            temp_csv_path = f.name
            
        try:
            copy_from_env("/tmp/census_report_export.csv", temp_csv_path)
            
            with open(temp_csv_path, 'r') as csvfile:
                reader = csv.reader(csvfile)
                rows = list(reader)
                
                if not rows:
                    feedback_parts.append("CSV file is empty.")
                else:
                    # Check Header (10 points)
                    header = [h.strip() for h in rows[0]]
                    expected_header = ["Unit", "Occupancy", "Status"]
                    if header == expected_header:
                        score += 10
                        feedback_parts.append("CSV Header correct.")
                    else:
                        feedback_parts.append(f"Header mismatch: {header} vs {expected_header}")
                    
                    # Check Data Rows (50 points split between calc and logic)
                    # We expect 5 rows of data
                    data_rows = rows[1:]
                    units_found = 0
                    calc_correct = 0
                    logic_correct = 0
                    
                    for row in data_rows:
                        if len(row) < 3: continue
                        unit = row[0].strip()
                        
                        if unit in ground_truth:
                            units_found += 1
                            gt = ground_truth[unit]
                            
                            # Check Occupancy % (25 points max)
                            try:
                                val_str = row[1].replace('%', '').strip()
                                val = float(val_str)
                                # Tolerance 0.2 for rounding differences (16.666 -> 16.7)
                                if abs(val - gt['pct']) <= 0.2:
                                    calc_correct += 1
                                else:
                                    feedback_parts.append(f"{unit} % mismatch: {val} != {gt['pct']}")
                            except ValueError:
                                feedback_parts.append(f"{unit} invalid number: {row[1]}")
                                
                            # Check Status Logic (25 points max)
                            status = row[2].strip()
                            if status == gt['status']:
                                logic_correct += 1
                            else:
                                feedback_parts.append(f"{unit} status mismatch: {status} != {gt['status']}")
                    
                    # Pro-rate score based on 5 expected units
                    total_expected = len(ground_truth)
                    if total_expected > 0:
                        score += int((calc_correct / total_expected) * 25)
                        score += int((logic_correct / total_expected) * 25)
                        
                        if units_found == total_expected and calc_correct == total_expected and logic_correct == total_expected:
                            feedback_parts.append("All data and logic verified correct.")
                        
        except Exception as e:
            feedback_parts.append(f"Failed to verify CSV content: {str(e)}")
        finally:
            if os.path.exists(temp_csv_path):
                os.unlink(temp_csv_path)
    else:
        feedback_parts.append("Output file not found or not created during task.")

    passed = score >= 70
    feedback = " ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }