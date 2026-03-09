#!/usr/bin/env python3
"""
Verifier for Generate Rating Curve task.
Checks if the agent ran the simulation, extracted valid physical data, and generated the required report/plot.
"""

import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_rating_curve(traj, env_info, task_info):
    """
    Verify the rating curve generation task.
    
    Criteria:
    1. Simulation executed (HDF file exists & new).
    2. Data extracted (CSV exists & contains valid Flow/WSE).
    3. Visual Output (PNG exists & reasonable size).
    4. Metadata/Reporting (Report file exists, consistent with CSV).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- 1. Load Task Result Metadata ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- 2. Verify Simulation Execution (15 pts) ---
    sim_status = result.get('simulation_output', {})
    if sim_status.get('exists') and sim_status.get('created_during_task'):
        score += 15
        feedback_parts.append("Simulation run successfully.")
    elif sim_status.get('exists'):
        feedback_parts.append("Simulation output exists but timestamp suggests it wasn't run during task.")
    else:
        feedback_parts.append("Simulation output (Muncie.p04.hdf) not found.")

    # --- 3. Verify CSV Data Content (35 pts) ---
    csv_status = result.get('csv_file', {})
    csv_valid = False
    csv_rows = 0
    
    if csv_status.get('exists') and csv_status.get('size', 0) > 0:
        # Fetch the CSV to inspect content
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/agent_csv_data.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                # Read header
                sample = f.read(1024)
                f.seek(0)
                has_header = csv.Sniffer().has_header(sample)
                reader = csv.DictReader(f)
                
                # Check columns (case insensitive)
                headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
                has_flow = any('flow' in h or 'discharge' in h for h in headers)
                has_wse = any('wse' in h or 'stage' in h or 'elev' in h or 'surface' in h for h in headers)
                
                if has_flow and has_wse:
                    score += 15
                    feedback_parts.append("CSV has correct columns.")
                    
                    # Check data validity
                    valid_values = 0
                    min_wse = 9999
                    max_wse = -9999
                    
                    for row in reader:
                        csv_rows += 1
                        try:
                            # Try to extract values based on index if names are messy, or loose matching
                            # We assume the user named them somewhat sanely as per instructions
                            flow_key = next(k for k in row.keys() if 'flow' in k.lower() or 'discharge' in k.lower())
                            wse_key = next(k for k in row.keys() if 'wse' in k.lower() or 'stage' in k.lower() or 'elev' in k.lower())
                            
                            f_val = float(row[flow_key])
                            w_val = float(row[wse_key])
                            
                            if f_val >= 0 and 700 < w_val < 1200: # Muncie range is roughly 900ish
                                valid_values += 1
                                min_wse = min(min_wse, w_val)
                                max_wse = max(max_wse, w_val)
                        except:
                            pass
                    
                    if valid_values >= 10:
                        score += 20
                        csv_valid = True
                        feedback_parts.append(f"CSV contains valid hydraulic data ({valid_values} rows).")
                    else:
                        feedback_parts.append(f"CSV content invalid or insufficient rows ({valid_values}).")
                else:
                    feedback_parts.append(f"CSV missing required columns (Found: {headers}).")
                    
        except Exception as e:
            feedback_parts.append(f"Failed to parse CSV: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Rating curve CSV file not found.")

    # --- 4. Verify Plot (20 pts) ---
    plot_status = result.get('plot_file', {})
    if plot_status.get('exists') and plot_status.get('size', 0) > 5000: # >5KB
        score += 20
        feedback_parts.append("Rating curve plot exists.")
    elif plot_status.get('exists'):
        score += 5
        feedback_parts.append("Rating curve plot exists but is suspiciously small (<5KB).")
    else:
        feedback_parts.append("Rating curve plot not found.")

    # --- 5. Verify Report & Cross-Consistency (20 pts) ---
    report_status = result.get('report_file', {})
    xs_status = result.get('xs_list_file', {})
    
    if report_status.get('exists'):
        score += 10
        feedback_parts.append("Report file exists.")
        
        # Check consistency if CSV was valid
        if csv_valid:
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/tmp/agent_report.txt", temp_report.name)
                with open(temp_report.name, 'r') as f:
                    content = f.read().lower()
                    
                    # Loose check for numbers
                    # We expect the report to mention flow/wse values. 
                    # Checking exact matching is hard due to float formatting, 
                    # but we can check if it looks like a report.
                    if "flow" in content and "wse" in content:
                        score += 10
                        feedback_parts.append("Report content appears relevant.")
                    else:
                        feedback_parts.append("Report content missing keywords (flow, wse).")
            except:
                pass
            finally:
                if os.path.exists(temp_report.name):
                    os.unlink(temp_report.name)
    
    # --- 6. Cross Sections List (10 pts) ---
    if xs_status.get('exists') and xs_status.get('size', 0) > 10:
        score += 10
        feedback_parts.append("Cross-section list exists.")

    # --- Final Scoring ---
    passed = (score >= 60) and sim_status.get('created_during_task') and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }