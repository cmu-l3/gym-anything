#!/usr/bin/env python3
"""
Verifier for galapagos_climate_data_extraction task.

Verification Strategy (Multi-criteria):
1. File Existence & Timestamps (20 pts): Ensure CSVs and TXT were created during the task.
2. CSV Validity (20 pts): Ensure both CSVs contain ~12 data rows, proving a 1-D Time extraction.
3. Summary Formatting (15 pts): TXT file contains requested headers and Target Lon = 270.
4. Scientific Correctness (20 pts): Hottest and wettest months are correctly identified.
   Due to the Humboldt Current, Galapagos (0N, 90W) peaks in Feb/Mar/Apr, NOT typical N/S hemisphere summer.
5. VLM Trajectory (25 pts): Verify agent used Panoply's line plot and export dialogs, not a hidden script.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galapagos_climate_data_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []

    # 1. Copy JSON and files from the environment
    tmp_dir = tempfile.mkdtemp()
    json_path = os.path.join(tmp_dir, 'result.json')
    temp_csv_path = os.path.join(tmp_dir, 'temp.csv')
    precip_csv_path = os.path.join(tmp_dir, 'precip.csv')
    summary_path = os.path.join(tmp_dir, 'summary.txt')

    try:
        copy_from_env('/tmp/galapagos_climate_data_extraction_result.json', json_path)
        copy_from_env('/tmp/galapagos_climate_data_extraction_temp.csv', temp_csv_path)
        copy_from_env('/tmp/galapagos_climate_data_extraction_precip.csv', precip_csv_path)
        copy_from_env('/tmp/galapagos_climate_data_extraction_summary.txt', summary_path)

        with open(json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve exported files: {e}"}

    task_start = int(result.get('task_start', 0))

    # Criterion 1: File Existence & Anti-Gaming (20 pts)
    temp_exists = result.get('temp_csv_exists', False)
    temp_mtime = result.get('temp_csv_mtime', 0)
    precip_exists = result.get('precip_csv_exists', False)
    precip_mtime = result.get('precip_csv_mtime', 0)

    files_valid = 0
    if temp_exists and temp_mtime >= task_start:
        files_valid += 1
    if precip_exists and precip_mtime >= task_start:
        files_valid += 1

    if files_valid == 2:
        score += 20
        feedback.append("Both CSV files exported during the task session.")
    elif files_valid == 1:
        score += 10
        feedback.append("Only one valid CSV file exported during task.")
    else:
        feedback.append("CSV files missing or not created during task.")

    # Criterion 2: CSV Validity (20 pts)
    # A Panoply 1D export should have headers and 12 rows of data (one for each month).
    def count_data_rows(csv_file):
        if not os.path.exists(csv_file):
            return 0
        try:
            with open(csv_file, 'r', errors='ignore') as f:
                lines = f.readlines()
            data_rows = 0
            for line in lines:
                # Basic heuristic: contains comma and numbers (typical data row)
                if ',' in line and any(c.isdigit() for c in line) and "Time" not in line and "Array" not in line:
                    data_rows += 1
            return data_rows
        except Exception:
            return 0

    temp_rows = count_data_rows(temp_csv_path)
    precip_rows = count_data_rows(precip_csv_path)

    csv_score = 0
    if 10 <= temp_rows <= 14:
        csv_score += 10
        feedback.append(f"Temperature CSV has valid 1D time-series shape ({temp_rows} rows).")
    else:
        feedback.append(f"Temperature CSV invalid shape ({temp_rows} rows, expected ~12).")

    if 10 <= precip_rows <= 14:
        csv_score += 10
        feedback.append(f"Precipitation CSV has valid 1D time-series shape ({precip_rows} rows).")
    else:
        feedback.append(f"Precipitation CSV invalid shape ({precip_rows} rows, expected ~12).")
        
    score += csv_score

    # Criterion 3: Summary Formatting & Scientific Logic (35 pts total)
    metadata = task_info.get('metadata', {})
    valid_months = metadata.get('valid_peak_months', ['february', 'feb', 'march', 'mar', 'april', 'apr', '2', '3', '4', '02', '03', '04'])
    
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    target_lon = ""
    target_lat = ""
    hot_month = ""
    wet_month = ""
    
    if report_exists and report_mtime >= task_start and os.path.exists(summary_path):
        try:
            with open(summary_path, 'r', errors='ignore') as f:
                content = f.read().lower()
            
            for line in content.splitlines():
                if "target_longitude:" in line:
                    target_lon = line.split(":", 1)[1].strip()
                elif "target_latitude:" in line:
                    target_lat = line.split(":", 1)[1].strip()
                elif "hottest_month:" in line:
                    hot_month = line.split(":", 1)[1].strip()
                elif "wettest_month:" in line:
                    wet_month = line.split(":", 1)[1].strip()
                    
            if target_lon == "270" and target_lat == "0":
                score += 15
                feedback.append("Report contains correct target coordinates (Lat: 0, Lon: 270).")
            else:
                feedback.append(f"Incorrect coordinates in report. Expected 0, 270. Got {target_lat}, {target_lon}.")
                
            if hot_month in valid_months and wet_month in valid_months:
                score += 20
                feedback.append(f"Scientific verification passed: Identified correct anomalous peak season ({hot_month}, {wet_month}).")
            else:
                feedback.append(f"Scientific verification failed: {hot_month}/{wet_month} are incorrect for Galapagos.")
                
        except Exception as e:
            feedback.append(f"Error parsing summary text: {e}")
    else:
        feedback.append("Summary report missing or not updated.")

    # Criterion 4: VLM Trajectory Verification (25 pts)
    # Prove the agent used the UI for Line Plot and Export, not a python script.
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames:
            prompt = (
                "You are reviewing an agent's workflow in NASA Panoply. "
                "Did the agent at any point create a 1D LINE PLOT (a graph with lines on X/Y axes, NOT a map) "
                "and interact with data export or coordinate/array settings? "
                "Respond in JSON: {\"used_line_plot\": true/false, \"reasoning\": \"...\"}"
            )
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_line_plot", False):
                    score += 25
                    feedback.append("VLM verified usage of Panoply line plot UI.")
                else:
                    feedback.append("VLM did not detect Panoply line plot usage.")
            else:
                # Fallback if VLM fails but files are perfect
                if score >= 55:
                    score += 25
                    feedback.append("VLM failed but programmatic evidence strongly suggests success.")
        else:
            feedback.append("No trajectory frames for VLM.")
    else:
        # Fallback if VLM missing
        if score >= 55:
            score += 25
            feedback.append("VLM not available, awarding points based on strong programmatic evidence.")

    # Cleanup temp
    try:
        import shutil
        shutil.rmtree(tmp_dir)
    except:
        pass

    passed = score >= 70 and files_valid > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }