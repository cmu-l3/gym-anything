#!/usr/bin/env python3
"""
Verifier for extract_longitudinal_profile task.

Checks:
1. Files existence (CSV, PNG, TXT, PY).
2. Anti-gaming (timestamps).
3. Data validity (CSV content analysis).
4. Plot validation (file size).
"""

import json
import os
import tempfile
import logging
import csv
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_longitudinal_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_min_elev = metadata.get('elevation_min', 900)
    expected_max_elev = metadata.get('elevation_max', 980)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Create a temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Load Main Result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

        # Extract file statuses
        csv_info = result.get("csv_file", {})
        plot_info = result.get("plot_file", {})
        summary_info = result.get("summary_file", {})
        script_info = result.get("script_file", {})
        hdf_info = result.get("hdf_result_file", {})

        # --- Criterion 1: Files Existence & Anti-Gaming (Timestamp) ---
        files_exist_score = 0
        if csv_info.get("exists") and csv_info.get("created_during_task"): files_exist_score += 10
        if plot_info.get("exists") and plot_info.get("created_during_task"): files_exist_score += 10
        if summary_info.get("exists") and summary_info.get("created_during_task"): files_exist_score += 5
        if script_info.get("exists") and script_info.get("created_during_task"): files_exist_score += 5
        
        score += files_exist_score
        feedback_parts.append(f"Files existence score: {files_exist_score}/30")

        # --- Criterion 2: Script Content Check ---
        if script_info.get("exists"):
            local_script = os.path.join(temp_dir, "extract_profile.py")
            try:
                copy_from_env(f"{result['results_dir']}/extract_profile.py", local_script)
                with open(local_script, 'r') as f:
                    script_content = f.read()
                    if "h5py" in script_content or "rashdf" in script_content:
                        score += 5
                        feedback_parts.append("Script imports HDF library.")
                    else:
                        feedback_parts.append("Script missing HDF library import.")
            except:
                feedback_parts.append("Could not retrieve script file.")
        
        # --- Criterion 3: CSV Data Validation ---
        csv_valid = False
        if csv_info.get("exists"):
            local_csv = os.path.join(temp_dir, "longitudinal_profile.csv")
            try:
                copy_from_env(f"{result['results_dir']}/longitudinal_profile.csv", local_csv)
                
                with open(local_csv, 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    if not rows:
                        feedback_parts.append("CSV file is empty.")
                    else:
                        # Check columns
                        required_cols = {'river_station', 'bed_elevation_ft', 'wse_ft', 'flow_depth_ft'}
                        if not required_cols.issubset(reader.fieldnames):
                            feedback_parts.append(f"CSV missing columns. Found: {reader.fieldnames}")
                        else:
                            score += 10  # Correct structure
                            
                            # Check Row Count
                            if len(rows) >= 5:
                                score += 10
                            else:
                                feedback_parts.append(f"Insufficient data rows: {len(rows)}")

                            # Check Data Consistency
                            consistent_rows = 0
                            in_range_rows = 0
                            
                            for row in rows:
                                try:
                                    bed = float(row['bed_elevation_ft'])
                                    wse = float(row['wse_ft'])
                                    depth = float(row['flow_depth_ft'])
                                    
                                    # Physical consistency: WSE >= Bed (allow small epsilon for dry beds)
                                    # Depth calculation check
                                    calc_depth = wse - bed
                                    if abs(calc_depth - depth) < 0.1:
                                        consistent_rows += 1
                                    
                                    # Range check
                                    if expected_min_elev <= bed <= expected_max_elev and expected_min_elev <= wse <= expected_max_elev:
                                        in_range_rows += 1
                                except ValueError:
                                    continue

                            if len(rows) > 0:
                                consistency_ratio = consistent_rows / len(rows)
                                range_ratio = in_range_rows / len(rows)
                                
                                if consistency_ratio > 0.9:
                                    score += 15
                                    feedback_parts.append("Data is physically consistent.")
                                else:
                                    feedback_parts.append(f"Data inconsistency detected ({int(consistency_ratio*100)}% valid).")
                                    
                                if range_ratio > 0.8:
                                    score += 10
                                    feedback_parts.append("Elevations within expected range.")
                                    csv_valid = True
                                else:
                                    feedback_parts.append("Elevations outside expected Muncie range.")
            except Exception as e:
                feedback_parts.append(f"Failed to validate CSV content: {str(e)}")

        # --- Criterion 4: Plot Validation ---
        if plot_info.get("exists"):
            if plot_info.get("size", 0) > 10240: # > 10KB
                score += 10
                feedback_parts.append("Plot file size is valid.")
            else:
                feedback_parts.append("Plot file is too small (likely empty).")

        # --- Criterion 5: Summary Consistency ---
        if summary_info.get("exists") and csv_valid:
            local_summary = os.path.join(temp_dir, "profile_summary.txt")
            try:
                copy_from_env(f"{result['results_dir']}/profile_summary.txt", local_summary)
                with open(local_summary, 'r') as f:
                    content = f.read()
                    # Basic check: contains numbers
                    if any(char.isdigit() for char in content):
                        score += 5
                        feedback_parts.append("Summary file contains data.")
            except:
                pass
        
        # --- Final Scoring ---
        passed = (score >= 60) and csv_valid
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }