#!/usr/bin/env python3
"""Verifier for longitudinal_physiological_sampling task in OpenICE."""

import json
import tempfile
import os
import csv
import re
import math

def verify_longitudinal_physiological_sampling(traj, env_info, task_info):
    """Verify data sampling task.
    
    Criteria:
    1. Device Created (20 pts)
    2. CSV File Exists (10 pts)
    3. Protocol Duration > 100s (20 pts) - Anti-gaming
    4. Data Quantity >= 5 samples (15 pts)
    5. Data Validity (15 pts) - Headers correct, values numeric and realistic
    6. Analysis Report Exists (10 pts)
    7. Analysis Accuracy (10 pts) - Report matches CSV data
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Device Created (20 pts)
    if result.get('device_created', False):
        score += 20
        feedback.append("Device creation detected.")
    else:
        feedback.append("FAIL: No Multiparameter Monitor detected.")

    # 2. CSV File Exists (10 pts)
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        score += 10
        feedback.append("CSV file exists.")
    else:
        feedback.append("FAIL: CSV file missing.")
        # Critical failure for subsequent checks
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Protocol Duration (20 pts)
    # Check if the file was last modified significantly after task start
    task_start = result.get('task_start_timestamp', 0)
    csv_mtime = result.get('csv_mtime', 0)
    duration = csv_mtime - task_start
    
    if duration > 100:
        score += 20
        feedback.append(f"Protocol duration satisfied ({duration}s).")
    else:
        feedback.append(f"FAIL: Protocol too short ({duration}s < 100s). Data collected too quickly.")

    # Retrieve CSV content for content analysis
    csv_rows = []
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Desktop/monitor_sample.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            # Handle potential header variations
            content = f.read().strip()
            if content:
                reader = csv.reader(content.splitlines())
                csv_rows = list(reader)
    except Exception as e:
        feedback.append(f"Error reading CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Data Quantity (15 pts)
    # Expect header + 5 rows = 6 lines
    if len(csv_rows) >= 6:
        score += 15
        feedback.append(f"Sufficient samples collected ({len(csv_rows)-1} samples).")
    elif len(csv_rows) > 1:
        # Partial credit
        score += 5
        feedback.append(f"Partial samples collected ({len(csv_rows)-1} samples).")
    else:
        feedback.append("FAIL: Insufficient data samples.")

    # 5. Data Validity (15 pts)
    valid_data = False
    hr_values = []
    spo2_values = []
    
    if len(csv_rows) > 0:
        header = [h.lower() for h in csv_rows[0]]
        # Check headers loosely
        if any('time' in h for h in header) and \
           any('heart' in h or 'hr' in h for h in header) and \
           any('spo2' in h or 'sat' in h for h in header):
            
            # Parse values
            valid_rows = 0
            for row in csv_rows[1:]:
                if len(row) >= 3:
                    try:
                        # Assuming order Time, HR, SpO2 or checking header index
                        # Simplified: try to find the numeric values in columns 1 and 2
                        hr = float(row[1])
                        spo2 = float(row[2])
                        
                        # Physiological bounds check (Simulator ranges)
                        if 40 <= hr <= 160 and 80 <= spo2 <= 100:
                            hr_values.append(hr)
                            spo2_values.append(spo2)
                            valid_rows += 1
                    except ValueError:
                        continue
            
            if valid_rows >= 5:
                score += 15
                valid_data = True
                feedback.append("Data values are valid and within physiological range.")
            else:
                feedback.append("FAIL: Data values missing or invalid.")
        else:
            feedback.append("FAIL: CSV Header incorrect.")

    # 6. Report Exists (10 pts)
    report_exists = result.get('report_exists', False)
    report_content = ""
    if report_exists:
        score += 10
        feedback.append("Analysis report exists.")
        
        # Read report content
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Desktop/sample_analysis.txt", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read().lower()
        except Exception:
            pass
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("FAIL: Analysis report missing.")

    # 7. Accuracy (10 pts)
    if valid_data and report_content:
        # Calculate stats from CSV
        avg_hr = sum(hr_values) / len(hr_values)
        min_spo2 = min(spo2_values)
        max_spo2 = max(spo2_values)
        
        # Check if these numbers appear in the report
        # Allow some formatting flexibility (int or float)
        hr_match = re.search(r'\d+', report_content) # Simple check for numbers
        
        # Check for approximate mean HR
        mean_hr_found = False
        for num in re.findall(r"[-+]?\d*\.\d+|\d+", report_content):
            try:
                if math.isclose(float(num), avg_hr, abs_tol=2.0):
                    mean_hr_found = True
                    break
            except ValueError:
                continue
                
        # Check for SpO2 range numbers
        range_found = False
        nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_content)]
        if any(math.isclose(x, min_spo2, abs_tol=1.0) for x in nums) and \
           any(math.isclose(x, max_spo2, abs_tol=1.0) for x in nums):
            range_found = True
            
        if mean_hr_found or range_found:
            score += 10
            feedback.append("Report values match CSV data.")
        else:
            feedback.append("Report values do not match CSV data calculations.")

    passed = score >= 60 and result.get('device_created', False) and duration > 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }