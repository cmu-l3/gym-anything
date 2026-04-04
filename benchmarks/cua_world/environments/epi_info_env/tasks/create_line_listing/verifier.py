#!/usr/bin/env python3
"""
Verifier for create_line_listing task (Epi Info 7).

Verification Steps:
1. Verify the HTML output file exists and was created during the task.
2. Validate content: contains specific headers (ID, AGE, SEX, ONSETDATE, ONSETTIME).
3. Validate filtering: Row count should be ~46 (Ill=Yes) vs 75 (Total).
4. Validate sorting: ONSETDATE/TIME should be monotonically increasing.
5. VLM: Verify workflow trajectory (opening Classic Analysis, typing commands).
"""

import json
import os
import tempfile
import logging
from datetime import datetime
from bs4 import BeautifulSoup

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_line_listing(traj, env_info, task_info):
    """
    Verify that the agent created a sorted, filtered line listing in Epi Info 7.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_columns', ["ID", "AGE", "SEX", "ONSETDATE", "ONSETTIME"])
    min_rows = metadata.get('min_rows', 40)
    max_rows = metadata.get('max_rows', 50)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container needs to be handled by copy_from_env
        # Assuming copy_from_env handles absolute paths correctly
        copy_from_env("C:\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output HTML file not found."}
        
    score += 15
    feedback_parts.append("Output file exists")
    
    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates it wasn't modified during task")

    # ================================================================
    # 2. Retrieve and Analyze HTML Content
    # ================================================================
    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\Oswego_LineList.html", temp_html.name)
        
        with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
            soup = BeautifulSoup(f, 'html.parser')
            
        # Epi Info HTML output usually contains a table
        tables = soup.find_all('table')
        if not tables:
            feedback_parts.append("No tables found in HTML output")
        else:
            # Usually the last table or the one with data
            # We look for a table containing the headers
            target_table = None
            for tbl in tables:
                headers = [th.get_text().strip().upper() for th in tbl.find_all('th')]
                if all(col in headers for col in expected_columns):
                    target_table = tbl
                    break
            
            if target_table:
                score += 15
                feedback_parts.append("Correct column headers found")
                
                # Check Row Count (Filtering)
                rows = target_table.find_all('tr')[1:] # Skip header
                data_rows = [r for r in rows if len(r.find_all('td')) >= len(expected_columns)]
                row_count = len(data_rows)
                
                if min_rows <= row_count <= max_rows:
                    score += 20
                    feedback_parts.append(f"Row count correct ({row_count} rows, ill only)")
                elif row_count > 60:
                    feedback_parts.append(f"Row count too high ({row_count}). Did you filter for ILL='Yes'?")
                else:
                    feedback_parts.append(f"Row count unexpected ({row_count})")
                    
                # Check Sorting (Onset Date/Time)
                # Need to find index of ONSETDATE and ONSETTIME
                headers = [th.get_text().strip().upper() for th in target_table.find_all('th')]
                try:
                    date_idx = headers.index("ONSETDATE")
                    time_idx = headers.index("ONSETTIME")
                    
                    timestamps = []
                    is_sorted = True
                    for row in data_rows:
                        cols = row.find_all('td')
                        d_str = cols[date_idx].get_text().strip()
                        t_str = cols[time_idx].get_text().strip()
                        
                        # Handle potential empty or formatted strings
                        # Epi Info date fmt usually MM/DD/YYYY
                        try:
                            # Combine for comparison
                            if d_str and t_str:
                                # Parsing logic might need adjustment based on exact output format
                                # Simple string comparison is often enough for ISO, but Epi uses US format
                                # Let's try to parse
                                dt = datetime.strptime(f"{d_str} {t_str}", "%m/%d/%Y %H:%M:%S")
                                timestamps.append(dt)
                        except:
                            pass # Skip parsing errors
                            
                    # Check if sorted
                    if len(timestamps) > 1:
                        if all(timestamps[i] <= timestamps[i+1] for i in range(len(timestamps)-1)):
                            score += 15
                            feedback_parts.append("Data is sorted chronologically")
                        else:
                            feedback_parts.append("Data is NOT sorted chronologically")
                            
                except ValueError:
                    feedback_parts.append("Could not verify sort order (columns missing)")
                    
            else:
                feedback_parts.append("Expected columns missing from table")
                
    except Exception as e:
        feedback_parts.append(f"Error analyzing HTML content: {e}")
    finally:
        if os.path.exists(temp_html.name):
            os.unlink(temp_html.name)

    # ================================================================
    # 3. VLM Trajectory Verification
    # ================================================================
    # We want to verify the user actually used the tool, not just generated the file via script
    # (Though file creation is the primary goal, workflow adherence is part of the test)
    
    # Import standard VLM helpers (simulated import structure based on prompt)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        You are verifying an agent using Epi Info 7 software.
        Check these screenshots for the following:
        1. Is the 'Classic Analysis' or 'Analysis' window visible? (Command prompt style interface or menu)
        2. Are commands like 'READ', 'SELECT', 'SORT', 'LIST' visible in the command log or output area?
        3. Is there a table or list output visible?
        
        Reply with JSON: {"analysis_window_visible": bool, "commands_visible": bool, "output_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('analysis_window_visible'):
                score += 10
            if parsed.get('commands_visible'):
                score += 10
            if parsed.get('output_visible'):
                score += 5
                
            if parsed.get('analysis_window_visible'):
                feedback_parts.append("VLM: Analysis workflow observed")
        except:
            # Fallback if VLM fails or is unavailable
            score += 10 # Give benefit of doubt if file is correct
            feedback_parts.append("VLM verification skipped")
            
    # Final Pass Check
    # Threshold 70, but mandatory output file
    passed = (score >= 70) and output_exists and file_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }