#!/usr/bin/env python3
"""
Verifier for summarize_cases_by_pathogen task.

Checks:
1. CSV output file exists and was created during the task.
2. CSV contains correct columns (PathogenName, OnsetQuarter, CaseCount, AvgAge).
3. Data is filtered correctly (confirmed cases only).
4. Data is aggregated correctly (sum of counts matches confirmed count).
5. VLM verification of the Classic Analysis workflow.
"""

import json
import os
import tempfile
import logging
import pandas as pd
from io import StringIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_summarize_cases(traj, env_info, task_info):
    """
    Verify the Epi Info summarization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Define temp paths
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        output_exists = result_data.get('output_exists', False)
        created_during_task = result_data.get('file_created_during_task', False)

        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
        
        score += 10
        feedback_parts.append("Output file found.")

        if created_during_task:
            score += 10
            feedback_parts.append("File created during task.")
        else:
            feedback_parts.append("File timestamp indicates it was not created during this session.")

        # 2. Retrieve and Validate CSV Content
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\FoodborneOutput\\pathogen_quarterly_summary.csv", temp_csv)
            
            # Use pandas to read CSV
            try:
                df = pd.read_csv(temp_csv)
            except:
                # Fallback if quotes/formatting is weird
                df = pd.read_csv(temp_csv, on_bad_lines='skip')
                
            # Clean column names (strip whitespace/quotes)
            df.columns = [c.strip().replace('"', '') for c in df.columns]
            
            # Check Columns
            required_cols = ['PathogenName', 'OnsetQuarter', 'CaseCount', 'AvgAge']
            # Allow some flexibility in naming (e.g. "Count", "Average Age")
            col_map = {c.lower(): c for c in df.columns}
            
            cols_found = 0
            if 'pathogenname' in col_map or 'pathogen' in col_map: cols_found += 1
            if 'onsetquarter' in col_map or 'quarter' in col_map: cols_found += 1
            if 'casecount' in col_map or 'count' in col_map or 'frequency' in col_map: cols_found += 1
            if 'avgage' in col_map or 'age' in col_map or 'mean' in col_map: cols_found += 1
            
            if cols_found >= 3:
                score += 15
                feedback_parts.append("Correct columns present.")
            else:
                feedback_parts.append(f"Missing required columns. Found: {list(df.columns)}")

            # Check Data Integrity
            if not df.empty:
                # Verify Row Count (expect roughly 6 pathogens * 4 quarters = 24 rows max, likely 15-24)
                row_count = len(df)
                if 12 <= row_count <= 30:
                    score += 10
                    feedback_parts.append(f"Row count reasonable ({row_count}).")
                else:
                    feedback_parts.append(f"Row count suspicious ({row_count}).")

                # Verify Total Count (Filter Check)
                # We expect ~510 confirmed cases out of 847.
                # Find the count column
                count_col = next((c for c in df.columns if 'count' in c.lower() or 'freq' in c.lower()), None)
                if count_col:
                    total_count = df[count_col].sum()
                    if 450 <= total_count <= 600:
                        score += 25
                        feedback_parts.append(f"Total count ({total_count}) matches expected Confirmed cases (filtering successful).")
                    elif total_count > 750:
                        feedback_parts.append(f"Total count ({total_count}) is too high - likely failed to filter 'Confirmed' cases.")
                    else:
                        feedback_parts.append(f"Total count ({total_count}) is out of expected range.")
                else:
                    feedback_parts.append("Could not identify Count column for validation.")

                # Verify Grouping
                pathogen_col = next((c for c in df.columns if 'pathogen' in c.lower()), None)
                if pathogen_col:
                    unique_pathogens = df[pathogen_col].nunique()
                    if unique_pathogens >= 5:
                        score += 10
                        feedback_parts.append("Grouping by Pathogen detected.")
            else:
                feedback_parts.append("CSV file is empty.")

        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV content: {e}")

    finally:
        if os.path.exists(temp_json):
            os.unlink(temp_json)
        if os.path.exists(temp_csv):
            os.unlink(temp_csv)

    # 3. VLM Verification (Trajectory)
    # Check if we saw the Classic Analysis window and READ/SELECT/SUMMARIZE commands
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of Epi Info 7 software.
        Did the user:
        1. Open the 'Classic Analysis' module (looks like a command console)?
        2. Use commands like 'READ', 'SELECT', 'SUMMARIZE' or 'WRITE'?
        3. Is there a visible output table summarizing data?
        
        Answer JSON: {"classic_analysis_used": bool, "commands_visible": bool, "summary_table_seen": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('classic_analysis_used') or parsed.get('commands_visible'):
                score += 20
                feedback_parts.append("Visual confirmation of Classic Analysis usage.")
        except:
            pass # VLM fail shouldn't crash verifier

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }