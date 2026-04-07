#!/usr/bin/env python3
"""
Verifier for arabica_coffee_climatology_validation task.

Occupation: Agricultural Commodity Analyst
Industry: Coffee Trading / Agricultural Economics
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 75):
  1. Temperature Line Plot (15 pts): minas_temp_cycle.png exists, >= 15KB, new.
  2. Precipitation Line Plot (15 pts): minas_precip_cycle.png exists, >= 15KB, new.
  3. CSV Export Exists (15 pts): minas_precip_timeseries.csv exists and is readable.
  4. CSV Structure Valid (25 pts): CSV contains exactly 12 numeric data rows (verifies 1D time series, not 2D map).
  5. CSV Data Plausible (10 pts): Minimum precipitation occurs in SH winter (indices 5, 6, 7).
  6. Report Correctness (20 pts): LON=315, driest/coolest in SH winter, sync=HIGH.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_arabica_coffee_climatology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    # 2. Retrieve CSV file
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_csv.close()

    try:
        copy_from_env('/tmp/arabica_coffee_climatology_validation_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
            
        # Try copying the CSV if it exists
        csv_available = False
        try:
            copy_from_env('/tmp/minas_precip_timeseries.csv', tmp_csv.name)
            if os.path.exists(tmp_csv.name) and os.path.getsize(tmp_csv.name) > 0:
                csv_available = True
        except Exception:
            pass
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Temperature Line Plot (15 pts)
    # ----------------------------------------------------------------
    temp_exists = result.get('temp_plot_exists', False)
    temp_mtime = int(result.get('temp_plot_mtime', 0))
    temp_size = int(result.get('temp_plot_size', 0))

    if temp_exists and temp_mtime >= task_start and temp_size >= 15000:
        score += 15
        feedback.append(f"Temperature line plot exported ({temp_size} bytes)")
    elif temp_exists and temp_mtime >= task_start:
        score += 7
        feedback.append(f"Temperature line plot present but small ({temp_size} bytes, expected >=15KB)")
    else:
        feedback.append("Temperature line plot missing or invalid.")

    # ----------------------------------------------------------------
    # Criterion 2: Precipitation Line Plot (15 pts)
    # ----------------------------------------------------------------
    precip_exists = result.get('precip_plot_exists', False)
    precip_mtime = int(result.get('precip_plot_mtime', 0))
    precip_size = int(result.get('precip_plot_size', 0))

    if precip_exists and precip_mtime >= task_start and precip_size >= 15000:
        score += 15
        feedback.append(f"Precipitation line plot exported ({precip_size} bytes)")
    elif precip_exists and precip_mtime >= task_start:
        score += 7
        feedback.append(f"Precipitation line plot present but small ({precip_size} bytes, expected >=15KB)")
    else:
        feedback.append("Precipitation line plot missing or invalid.")

    # ----------------------------------------------------------------
    # Criterion 3: CSV Export Exists (15 pts)
    # ----------------------------------------------------------------
    csv_exists = result.get('csv_data_exists', False)
    csv_mtime = int(result.get('csv_data_mtime', 0))
    
    if csv_exists and csv_mtime >= task_start:
        score += 15
        feedback.append("CSV export file successfully created.")
    else:
        feedback.append("CSV export file missing or not updated.")

    # ----------------------------------------------------------------
    # Criterion 4 & 5: CSV Structure Valid (25 pts) & Plausible Data (10 pts)
    # ----------------------------------------------------------------
    data_rows = []
    if csv_available:
        try:
            with open(tmp_csv.name, 'r', errors='replace') as f:
                for line in f:
                    # Panoply exports can be comma or tab separated. Convert tabs to commas.
                    clean_line = line.replace('\t', ',')
                    parts = [p.strip().strip('"') for p in clean_line.split(',')]
                    # If line has at least 2 columns and the last is a float, it's a data row
                    if len(parts) >= 2:
                        try:
                            val = float(parts[-1])
                            data_rows.append(val)
                        except ValueError:
                            continue
        except Exception as e:
            logger.error(f"Error parsing CSV: {e}")

    num_rows = len(data_rows)
    # Exactly 12 rows means it's a 1D time series. (2D maps will have hundreds/thousands of rows)
    if num_rows == 12:
        score += 25
        feedback.append("CSV Structure: Valid 1D time series extracted (exactly 12 data rows).")
        
        # Plausible data check: Southern Hemisphere winter (indices 5, 6, 7 = Jun, Jul, Aug)
        # Find index of minimum precipitation
        min_val = min(data_rows)
        min_idx = data_rows.index(min_val)
        
        if 4 <= min_idx <= 8:
            score += 10
            feedback.append(f"CSV Data Plausible: Minimum precipitation occurs at index {min_idx} (SH Winter).")
        else:
            feedback.append(f"CSV Data Anomalous: Minimum precipitation at index {min_idx}, expected Jun-Sep.")
    elif num_rows > 12:
        feedback.append(f"CSV Structure Invalid: Found {num_rows} data rows. Agent likely exported a 2D map instead of 1D time series.")
    elif csv_available:
        feedback.append(f"CSV Structure Invalid: Found {num_rows} data rows, expected exactly 12.")

    # Cleanup CSV temp file
    if os.path.exists(tmp_csv.name):
        os.unlink(tmp_csv.name)

    # ----------------------------------------------------------------
    # Criterion 6: Report Correctness (20 pts)
    # ----------------------------------------------------------------
    target_lat = result.get('target_lat', '').strip()
    target_lon = result.get('target_lon', '').strip()
    driest_month = result.get('driest_month', '').strip().lower()
    sync_potential = result.get('flowering_sync', '').strip().upper()

    report_pts = 0
    
    if target_lon == '315' or target_lon == '315.0':
        report_pts += 5
        feedback.append("Report: Target Longitude correctly mapped to 315°E.")
    else:
        feedback.append(f"Report: Target Longitude incorrect (got '{target_lon}', expected 315).")
        
    sh_winter_months = ['jun', 'jul', 'aug', 'sep']
    if any(m in driest_month for m in sh_winter_months):
        report_pts += 10
        feedback.append(f"Report: Identified proper dry season ({driest_month}).")
        
    if sync_potential == 'HIGH':
        report_pts += 5
        feedback.append("Report: Flowering sync correctly identified as HIGH.")

    score += report_pts

    # ----------------------------------------------------------------
    # Final Evaluation
    # ----------------------------------------------------------------
    # To pass, the agent must score >= 75 AND must have successfully exported the 1D CSV structure.
    passed = (score >= 75) and (num_rows == 12)
    
    # Try VLM as a secondary fallback to provide rich feedback on the trajectory
    try:
        query_vlm = env_info.get('query_vlm')
        from gym_anything.vlm import get_final_screenshot
        final_img = get_final_screenshot(traj)
        if query_vlm and final_img:
            vlm_prompt = "Look at this Panoply window. Does it show a 1D line plot graph (a line charting values over time)? Answer yes or no."
            vlm_resp = query_vlm(prompt=vlm_prompt, image=final_img)
            if vlm_resp.get('success'):
                logger.info(f"VLM says: {vlm_resp.get('parsed', {}).get('response', '')}")
    except Exception as e:
        logger.warning(f"VLM supplemental check failed: {e}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }