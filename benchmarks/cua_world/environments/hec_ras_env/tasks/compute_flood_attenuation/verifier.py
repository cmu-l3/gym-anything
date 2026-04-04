#!/usr/bin/env python3
"""
Verifier for compute_flood_attenuation task.

Checks:
1. CSV file exists, is valid, contains Time/Upstream/Downstream columns.
2. Report file exists and contains key metrics (Attenuation, Lag, Volume).
3. Plot file exists.
4. Data consistency:
   - Peak flows in CSV match Summary.
   - Attenuation % is calculated correctly.
   - Data is physically plausible (Downstream peak <= Upstream peak for attenuation).
"""

import json
import os
import tempfile
import logging
import csv
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flood_attenuation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files for artifacts
    result_json_path = tempfile.mktemp(suffix='.json')
    csv_path = tempfile.mktemp(suffix='.csv')
    report_path = tempfile.mktemp(suffix='.txt')

    score = 0
    feedback_parts = []
    
    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check File Existence & Timestamp (Anti-gaming)
        csv_status = task_result.get('csv_file', {})
        report_status = task_result.get('report_file', {})
        plot_status = task_result.get('plot_file', {})
        hdf_status = task_result.get('hdf_file', {})

        if not csv_status.get('exists'):
            return {"passed": False, "score": 0, "feedback": "CSV data file not found."}
        
        score += 10  # CSV exists
        feedback_parts.append("CSV file found.")

        if csv_status.get('created_during_task'):
            score += 5
        else:
            feedback_parts.append("Warning: CSV not created during this task session.")

        if report_status.get('exists'):
            score += 10
            feedback_parts.append("Summary report found.")
        else:
            feedback_parts.append("Summary report missing.")

        if plot_status.get('exists') and plot_status.get('size', 0) > 1024:
            score += 10
            feedback_parts.append("Plot image found.")
        else:
            feedback_parts.append("Plot image missing or empty.")

        if hdf_status.get('exists'):
            score += 5
            feedback_parts.append("Simulation results HDF5 found.")
        else:
            feedback_parts.append("Simulation results missing (did you run the simulation?).")

        # 3. Analyze CSV Content
        try:
            copy_from_env("/tmp/flood_attenuation_data.csv", csv_path)
            
            times = []
            q_upstream = []
            q_downstream = []
            
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames or []
                
                # Check headers
                required_cols = ['Time_hours', 'Flow_Upstream_cfs', 'Flow_Downstream_cfs']
                header_match = all(any(req.lower() in h.lower() for h in headers) for req in required_cols)
                
                if header_match:
                    score += 5
                else:
                    feedback_parts.append(f"CSV headers malformed. Found: {headers}")
                
                for row in reader:
                    # Robust parsing finding keys
                    t_key = next((k for k in row.keys() if 'time' in k.lower()), None)
                    u_key = next((k for k in row.keys() if 'upstream' in k.lower()), None)
                    d_key = next((k for k in row.keys() if 'downstream' in k.lower()), None)
                    
                    if t_key and u_key and d_key:
                        try:
                            times.append(float(row[t_key]))
                            q_upstream.append(float(row[u_key]))
                            q_downstream.append(float(row[d_key]))
                        except ValueError:
                            continue

            if len(times) > 50:
                score += 5
                feedback_parts.append(f"CSV contains valid data ({len(times)} rows).")
            else:
                feedback_parts.append("CSV contains too few rows.")

            # Calculate metrics from CSV
            max_u = max(q_upstream) if q_upstream else 0
            max_d = max(q_downstream) if q_downstream else 0
            
            if max_u > 1000 and max_d > 1000:
                score += 10 # Data looks physical
            else:
                feedback_parts.append(f"Peak flows look suspicious (U:{max_u}, D:{max_d}).")

            attenuation_calc = max_u - max_d
            attenuation_pct_calc = (attenuation_calc / max_u) * 100 if max_u > 0 else 0
            
            # Check physical realism (Attenuation should be positive for a flood wave in this reach)
            if attenuation_calc > 0:
                score += 5
            
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {e}")

        # 4. Analyze Report Content
        report_text = ""
        try:
            copy_from_env("/tmp/flood_attenuation_summary.txt", report_path)
            with open(report_path, 'r') as f:
                report_text = f.read().lower()
            
            # Check for keywords
            keywords = ['peak', 'attenuation', 'volume', 'lag', 'cfs', 'acre-ft']
            found_keywords = sum(1 for k in keywords if k in report_text)
            if found_keywords >= 4:
                score += 10
                feedback_parts.append("Report contains expected terminology.")
            
            # Extract numbers from report to compare with CSV
            # Regex to find numbers near keywords
            # This is heuristic; looking for the values we calculated from CSV
            
            # Check Peak Upstream
            if any(str(int(max_u)) in report_text or f"{max_u:.1f}" in report_text for _ in [1]):
                score += 5
                feedback_parts.append("Reported upstream peak matches CSV.")
            
            # Check Attenuation %
            if any(f"{attenuation_pct_calc:.1f}" in report_text or f"{int(attenuation_pct_calc)}" in report_text for _ in [1]):
                score += 10
                feedback_parts.append("Reported attenuation % matches CSV calculation.")
            
            # Check Volume Difference (Just existence of a % value)
            if re.search(r'volume.*difference.*%', report_text) or re.search(r'difference.*%', report_text):
                 score += 5
                 feedback_parts.append("Report includes volume difference.")

        except Exception as e:
            feedback_parts.append(f"Error analyzing Report: {e}")
            
        # 5. Final Calculation
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        for p in [result_json_path, csv_path, report_path]:
            if os.path.exists(p):
                os.unlink(p)