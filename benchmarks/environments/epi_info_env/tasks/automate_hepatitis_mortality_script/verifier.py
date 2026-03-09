#!/usr/bin/env python3
"""
Verifier for automate_hepatitis_mortality_script task.

Verifies:
1. PGM script exists and was created during task.
2. Output CSV exists and was created during task.
3. Output CSV contains correct filtered data (Class 1 = Die).
4. Output CSV row count matches ground truth (32 deaths).
"""

import json
import os
import csv
import io
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hepatitis_script(traj, env_info, task_info):
    # Setup connection
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_death_count = metadata.get('expected_death_count', 32)
    
    score = 0
    feedback = []
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Script Creation (20 pts)
    if result.get('script_exists'):
        score += 20
        feedback.append("Script file created.")
    else:
        feedback.append("Script file not found or not saved.")

    # 3. Verify Output Creation (20 pts)
    output_exists = result.get('output_exists')
    if output_exists:
        score += 20
        feedback.append("Output CSV created.")
    else:
        feedback.append("Output CSV not found.")

    # 4. Verify Content (Logic & Filtering)
    content_correct = False
    row_count = 0
    bad_rows = 0
    
    if output_exists:
        # Fetch the CSV file
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            output_path = result.get('output_path', 'C:\\Users\\Docker\\Documents\\Output\\mortality_review_list.csv')
            # Handle potential Windows path issues in copy_from_env if needed, 
            # usually the function handles string paths correctly.
            copy_from_env(output_path, temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Epi Info might output quotes, so we use csv reader
                reader = csv.DictReader(f)
                
                # Check headers
                headers = reader.fieldnames if reader.fieldnames else []
                # Expected headers: Class, Age... OR just Class if they selected one. 
                # But task implied full record export of filtered list.
                
                for row in reader:
                    row_count += 1
                    # Check Class/Outcome
                    # 'Class' is original (1 or 2). 'Outcome' is derived ("Deceased" or "Alive").
                    # We accept either if the logic holds (Class=1 or Outcome="Deceased")
                    
                    is_deceased = False
                    
                    # Check Class column if exists
                    if 'Class' in row and row['Class'].strip() == '1':
                        is_deceased = True
                    
                    # Check Outcome column if exists
                    if 'Outcome' in row and 'Deceased' in row['Outcome']:
                        is_deceased = True
                        
                    if not is_deceased:
                        bad_rows += 1
                        
        except Exception as e:
            feedback.append(f"Error analyzing output CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

        # Content Scoring (30 pts for filtering logic, 20 pts for completeness)
        
        # Filtering Logic
        if row_count > 0 and bad_rows == 0:
            score += 30
            feedback.append("Filtering logic correct (only deceased patients).")
            content_correct = True
        elif row_count > 0 and bad_rows > 0:
            feedback.append(f"Filtering logic incorrect. Found {bad_rows} non-deceased records.")
        else:
            feedback.append("Output file is empty.")

        # Completeness (Target 32 records)
        if content_correct:
            if abs(row_count - expected_death_count) <= 2: # Tolerance +/- 2
                score += 20
                feedback.append(f"Row count correct ({row_count}).")
            else:
                score += 10 # Partial credit if filtering is right but count is off
                feedback.append(f"Row count mismatch. Expected ~{expected_death_count}, found {row_count}.")
    
    # Recoding Check (10 pts)
    # Since we can't easily parse the binary/text PGM for logic without a parser,
    # we infer the recode success if the 'Outcome' column exists in CSV or 
    # if the agent used Class=1 correctly. 
    # For strictness, if the CSV has 'Outcome' column, full points.
    # We'll rely on the CSV analysis above.
    if output_exists and content_correct:
         score += 10 # Bonus for achieving the goal implies logic was sufficient
    
    # Pass check
    passed = score >= 70 and content_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }