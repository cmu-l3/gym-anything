#!/usr/bin/env python3
"""
Verifier for ROC Analysis with Data Cleaning task.
Evaluates:
1. Data Cleaning: Clean CSV exists and '0' values in Glucose/BMI are removed (replaced with null/empty).
2. Analysis: HTML report exists and contains ROC results.
3. VLM: Trajectory shows use of Classic Analysis interface.
"""

import json
import os
import tempfile
import logging
import csv
import io
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils (assuming environment setup)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM modules not available")

def verify_roc_analysis(traj, env_info, task_info):
    """
    Verify the Epi Info 7 data cleaning and ROC analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Define paths (from task metadata or defaults)
    # Note: Windows paths in env need to be handled carefully
    win_docs_path = "C:\\Users\\Docker\\Documents\\EpiData" # Windows path in container
    clean_csv_win_path = f"{win_docs_path}\\diabetes_clean.csv"
    report_win_path = f"{win_docs_path}\\roc_results.html"
    result_json_win_path = "C:\\Users\\Docker\\Documents\\task_result.json"

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Task Result Metadata
    # ---------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env(result_json_win_path, tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy task result: {e}")
            feedback.append("Could not retrieve task status (export script may have failed).")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # ---------------------------------------------------------
    # 2. Verify Cleaned Data (40 Points)
    # ---------------------------------------------------------
    clean_file_exists = task_result.get('clean_file_exists', False)
    clean_data_valid = False
    
    if clean_file_exists:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp_csv:
            try:
                copy_from_env(clean_csv_win_path, tmp_csv.name)
                
                # Analyze CSV content
                with open(tmp_csv.name, 'r', encoding='utf-8-sig') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    if not rows:
                        feedback.append("Cleaned CSV is empty.")
                    else:
                        zero_glucose = 0
                        zero_bmi = 0
                        total_rows = len(rows)
                        
                        # Indices of Glucose/BMI columns
                        # Epi Info export might change case, so handle robustly
                        headers = [h.lower() for h in reader.fieldnames]
                        g_key = next((k for k in reader.fieldnames if k.lower() == 'glucose'), None)
                        b_key = next((k for k in reader.fieldnames if k.lower() == 'bmi'), None)
                        
                        if not g_key or not b_key:
                            feedback.append("Cleaned CSV missing required columns (Glucose/BMI).")
                        else:
                            for row in rows:
                                # Check for 0 strings or 0.0 floats
                                g_val = row[g_key].strip()
                                b_val = row[b_key].strip()
                                
                                try:
                                    if float(g_val) == 0: zero_glucose += 1
                                except ValueError: pass # Not a number (empty is good)
                                
                                try:
                                    if float(b_val) == 0: zero_bmi += 1
                                except ValueError: pass

                            # Raw data has ~5 zero glucose and ~11 zero BMI
                            if zero_glucose == 0 and zero_bmi == 0:
                                score += 40
                                clean_data_valid = True
                                feedback.append(f"Data cleaned successfully ({total_rows} records).")
                            else:
                                score += 10 # Partial credit for exporting
                                feedback.append(f"Data export found but cleaning incomplete (Found {zero_glucose} zero-Glucose and {zero_bmi} zero-BMI records).")
            
            except Exception as e:
                feedback.append(f"Error analyzing cleaned CSV: {e}")
            finally:
                if os.path.exists(tmp_csv.name):
                    os.unlink(tmp_csv.name)
    else:
        feedback.append("Cleaned data file not found.")

    # ---------------------------------------------------------
    # 3. Verify HTML Report Content (30 Points)
    # ---------------------------------------------------------
    report_exists = task_result.get('report_file_exists', False)
    
    if report_exists:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.html') as tmp_html:
            try:
                copy_from_env(report_win_path, tmp_html.name)
                with open(tmp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for ROC keywords
                    if "receiver operating characteristic" in content or "roc curve" in content:
                        score += 10
                        feedback.append("Report contains ROC section.")
                        
                        # Check for variable names in report
                        if "glucose" in content:
                            score += 10
                            feedback.append("Report contains Glucose analysis.")
                        if "bmi" in content:
                            score += 10
                            feedback.append("Report contains BMI analysis.")
                    else:
                        feedback.append("Report file exists but ROC analysis not detected.")
                        
            except Exception as e:
                feedback.append(f"Error analyzing report: {e}")
            finally:
                if os.path.exists(tmp_html.name):
                    os.unlink(tmp_html.name)
    else:
        feedback.append("Analysis report not found.")

    # ---------------------------------------------------------
    # 4. VLM Trajectory Verification (30 Points)
    # ---------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        You are verifying an agent using Epi Info 7 Classic Analysis software.
        Check the images for the following:
        1. Is the 'Classic Analysis' window visible? (Command tree on left, output on right)
        2. Is there evidence of the 'ROC Curves' command being used?
        3. Is there evidence of data cleaning (Recode, Assign, or editing values)?
        
        Return JSON:
        {
            "classic_analysis_visible": boolean,
            "roc_command_visible": boolean,
            "cleaning_visible": boolean
        }
        """
        
        try:
            result = query_vlm(images=frames + [final_ss], prompt=prompt)
            parsed = result.get('parsed', {})
            
            if parsed.get('classic_analysis_visible'):
                vlm_score += 10
            if parsed.get('roc_command_visible'):
                vlm_score += 10
            if parsed.get('cleaning_visible'):
                vlm_score += 10
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: give partial credit if data verification passed strongly
            if clean_data_valid:
                vlm_score = 30
    
    score += vlm_score
    feedback.append(f"VLM Verification: {vlm_score}/30 points.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Threshold: Must have cleaned data AND produced some report
    passed = (clean_data_valid and report_exists and score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }