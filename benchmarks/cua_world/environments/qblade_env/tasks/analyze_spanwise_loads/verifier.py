#!/usr/bin/env python3
"""
Verifier for analyze_spanwise_loads task.

Verification Strategy:
1. Data File Verification:
   - Check if export file exists and contains valid numeric data.
   - Verify it has at least 3 columns (Position, Fn, Ft).
   - Verify values are physically reasonable (non-zero loads).
2. Report Verification:
   - Extract the max Fn value from the report file.
   - Calculate the actual max Fn from the data file.
   - Compare them (consistency check).
3. Anti-Gaming:
   - Verify files were created during task.
4. VLM Verification (Optional trajectory check):
   - Confirm graph view was active.
"""

import json
import os
import tempfile
import logging
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_data_file(file_path):
    """
    Parses QBlade/XFoil style text export.
    Returns a list of rows, where each row is a list of floats.
    """
    data = []
    try:
        with open(file_path, 'r') as f:
            for line in f:
                # Skip comments/headers
                if line.strip().startswith('#') or not line.strip():
                    continue
                # Try to parse numbers
                try:
                    # Split by whitespace
                    parts = line.strip().split()
                    # Convert to floats
                    row = [float(p) for p in parts]
                    if len(row) > 0:
                        data.append(row)
                except ValueError:
                    continue
    except Exception as e:
        logger.error(f"Error reading data file: {e}")
    return data

def verify_analyze_spanwise_loads(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Setup temp files
    result_json_path = tempfile.mktemp(suffix='.json')
    data_export_path = tempfile.mktemp(suffix='.txt')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load JSON Result
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
            
        # 2. Verify Data Export Existence (20 pts)
        if result.get('data_exists') and result.get('data_created_during_task'):
            score += 20
            feedback_parts.append("Data export file created successfully")
            
            # 3. Verify Data Content (30 pts)
            # Copy the actual text file
            if result.get('exported_data_path'):
                try:
                    copy_from_env(result['exported_data_path'], data_export_path)
                    
                    rows = parse_data_file(data_export_path)
                    
                    # Check dimensions
                    if len(rows) > 5:
                        score += 10
                        feedback_parts.append(f"Data file contains content ({len(rows)} rows)")
                        
                        # Check columns (Expect at least 3: Pos, Fn, Ft)
                        # Some exports might have more
                        num_cols = len(rows[0])
                        if num_cols >= 3:
                            score += 10
                            feedback_parts.append(f"Valid column structure ({num_cols} cols)")
                        else:
                            feedback_parts.append(f"Missing columns (found {num_cols}, expected >=3)")
                            
                        # Physics Check (10 pts)
                        # Find Max Normal Force (usually 2nd or 3rd column depending on selection order)
                        # We don't know exact column order without headers (which might be stripped),
                        # but typically Fn is the largest magnitude column often.
                        # Let's look for a column with a reasonable max value.
                        max_vals = [max([r[i] for r in rows]) for i in range(num_cols)]
                        valid_physics = False
                        detected_max_fn = 0
                        
                        # Heuristic: Fn max usually > 100 N/m for a turbine at 12m/s
                        for val in max_vals:
                            if val > metadata.get('physics_validation', {}).get('min_peak_load_n', 100):
                                valid_physics = True
                                # Assume the largest max value is likely Fn or similar
                                if val > detected_max_fn:
                                    detected_max_fn = val
                        
                        if valid_physics:
                            score += 10
                            feedback_parts.append("Data values physically reasonable (Peak load > 100)")
                        else:
                            feedback_parts.append("Data values seem too low/zero for loaded simulation")
                            
                    else:
                        feedback_parts.append("Data file is empty or unparseable")
                except Exception as e:
                    feedback_parts.append(f"Error analyzing data file: {str(e)}")
        else:
            feedback_parts.append("Data export file missing or not created during task")

        # 4. Verify Report (30 pts)
        report_content = result.get('report_content', "")
        report_exists = result.get('report_exists', False)
        
        report_val = None
        
        if report_exists and result.get('report_created_during_task'):
            score += 10
            feedback_parts.append("Report file created")
            
            # Parse value using regex
            # Matches: "Max_Fn = 1234.56" or just "1234.56"
            match = re.search(r"[-+]?\d*\.\d+|\d+", report_content)
            if match:
                try:
                    report_val = float(match.group())
                    score += 10 # Found a number
                    feedback_parts.append(f"Report contains value: {report_val}")
                except:
                    feedback_parts.append("Could not parse number from report")
            else:
                feedback_parts.append("No numeric value found in report")
        else:
            feedback_parts.append("Report file missing")

        # 5. Consistency Check (20 pts)
        # Compare reported value to detected max value from data
        if report_val is not None and 'detected_max_fn' in locals() and detected_max_fn > 0:
            # Allow 5% tolerance or +/- 10 units (rounding diffs)
            diff = abs(report_val - detected_max_fn)
            tolerance = max(0.05 * detected_max_fn, 10.0)
            
            # Also check if they reported a different column (e.g. Ft)
            # Check against all column maxes
            match_found = False
            for col_max in max_vals:
                if abs(report_val - col_max) < tolerance:
                    match_found = True
                    break
            
            if match_found:
                score += 20
                feedback_parts.append("Reported value matches exported data")
            else:
                feedback_parts.append(f"Reported value ({report_val}) does not match data max ({detected_max_fn:.2f})")
        elif report_val is not None:
             # If we couldn't parse data file but have report, partial credit check
             # Check if physically plausible range [500, 100000]
             if 500 < report_val < 100000:
                 score += 10 # Partial credit
                 feedback_parts.append("Reported value in plausible range (Data file check skipped)")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(result_json_path): os.remove(result_json_path)
        if os.path.exists(data_export_path): os.remove(data_export_path)

    # Final Pass Decision
    # Pass if: Data exists (20) + Data Content good (20) + Report exists (10) + Report matches (20) + Physics (10) = 80
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }