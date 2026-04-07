#!/usr/bin/env python3
"""
Verifier for Agricultural Split-Plot Design Analysis.

Criteria:
1. ANOVA CSV exists and is new (10 pts)
2. ANOVA Model Correctness (40 pts):
   - Variety F-value ~ 1.79 (indicates correct Error(B/V) term)
   - Nitrogen F-value ~ 37.69
3. Interaction Plot exists and is new (15 pts)
4. Plot Visualization Quality via VLM (35 pts):
   - Check axes, grouping, and lines.

Pass Threshold: 60/100 points
"""

import json
import os
import tempfile
import csv
import math
import logging

logger = logging.getLogger(__name__)

def verify_agri_split_plot_oats(traj, env_info, task_info):
    """Verify split-plot analysis and visualization."""
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Load task metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_variety_f = metadata.get('expected_variety_f_value', 1.79)
    expected_nitrogen_f = metadata.get('expected_nitrogen_f_value', 37.69)
    tolerance = metadata.get('f_value_tolerance', 0.1)
    
    # Retrieve result JSON
    result_json_path = "/tmp/task_result.json"
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: ANOVA CSV Existence (10 pts)
    # ---------------------------------------------------------
    if result_data.get('csv_exists') and result_data.get('csv_is_new'):
        score += 10
        feedback.append("ANOVA results file created successfully.")
    else:
        feedback.append("ANOVA results file missing or not updated.")

    # ---------------------------------------------------------
    # Criterion 2: Statistical Model Verification (40 pts)
    # ---------------------------------------------------------
    model_passed = False
    
    if result_data.get('csv_exists'):
        csv_path = result_data.get('csv_path')
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        try:
            copy_from_env(csv_path, temp_csv.name)
            
            variety_f_found = None
            nitrogen_f_found = None
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                # Normalize headers to lowercase to handle slight naming variations
                reader.fieldnames = [h.lower() for h in (reader.fieldnames or [])]
                
                for row in reader:
                    # Look for term/source columns
                    term = row.get('term', '') or row.get('source', '') or row.get('variable', '')
                    term = term.lower()
                    
                    # Look for statistic/f/f.value columns
                    f_val_str = row.get('statistic', '') or row.get('f', '') or row.get('f.value', '') or row.get('f_value', '')
                    
                    if not f_val_str:
                        continue
                        
                    try:
                        f_val = float(f_val_str)
                        if 'variety' in term or 'v' == term.strip():
                            variety_f_found = f_val
                        elif 'nitrogen' in term or 'n' == term.strip():
                            nitrogen_f_found = f_val
                    except ValueError:
                        continue

            # Verify Variety F-value (Crucial for Split-Plot)
            # Correct: ~1.79 (Error: B/V)
            # Incorrect (Factorial): ~0.6 (Error: Residual)
            if variety_f_found is not None:
                if math.isclose(variety_f_found, expected_variety_f, abs_tol=tolerance):
                    score += 30
                    feedback.append(f"Correct Split-Plot model used! Variety F-value {variety_f_found:.2f} matches expected.")
                    model_passed = True
                elif math.isclose(variety_f_found, 0.6, abs_tol=0.2):
                    feedback.append(f"Incorrect model structure. Variety F-value {variety_f_found:.2f} suggests simple factorial ANOVA instead of split-plot.")
                else:
                    feedback.append(f"Incorrect Variety F-value: {variety_f_found:.2f} (Expected ~{expected_variety_f}).")
            else:
                feedback.append("Could not find 'Variety' row or F-value in CSV.")

            # Verify Nitrogen F-value
            if nitrogen_f_found is not None:
                if math.isclose(nitrogen_f_found, expected_nitrogen_f, abs_tol=1.0):
                    score += 10
                    feedback.append(f"Nitrogen F-value {nitrogen_f_found:.2f} is correct.")
                else:
                    feedback.append(f"Incorrect Nitrogen F-value: {nitrogen_f_found:.2f} (Expected ~{expected_nitrogen_f}).")
            else:
                feedback.append("Could not find 'Nitrogen' row or F-value in CSV.")

        except Exception as e:
            feedback.append(f"Error parsing ANOVA CSV: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # ---------------------------------------------------------
    # Criterion 3: Plot Existence (15 pts)
    # ---------------------------------------------------------
    plot_exists = False
    if result_data.get('plot_exists') and result_data.get('plot_is_new'):
        if result_data.get('plot_size_bytes', 0) > 10240: # > 10KB
            score += 15
            plot_exists = True
            feedback.append("Interaction plot file created and has reasonable size.")
        else:
            feedback.append("Interaction plot created but seems empty/too small.")
    else:
        feedback.append("Interaction plot file missing.")

    # ---------------------------------------------------------
    # Criterion 4: VLM Plot Verification (35 pts)
    # ---------------------------------------------------------
    if plot_exists and query_vlm:
        plot_path = result_data.get('plot_path')
        temp_plot = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        try:
            copy_from_env(plot_path, temp_plot.name)
            
            prompt = """
            You are verifying a statistical interaction plot from an agricultural experiment.
            The plot should show:
            1. Y-axis representing 'Yield' (values roughly 60-140).
            2. X-axis representing 'Nitrogen' levels (0.0, 0.2, 0.4, 0.6).
            3. Three distinct lines representing different Oat Varieties.
            
            Does this image look like a valid interaction plot meeting these criteria?
            Respond with JSON: {"valid": boolean, "lines_count": int, "has_legend": boolean, "reason": string}
            """
            
            vlm_response = query_vlm(prompt=prompt, image=temp_plot.name)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("valid"):
                    score += 35
                    feedback.append("VLM confirms plot is valid.")
                else:
                    feedback.append(f"VLM rejected plot: {parsed.get('reason')}")
            else:
                # Fallback if VLM fails but plot exists (give partial credit)
                score += 15
                feedback.append("VLM check failed, granting partial credit for file existence.")
                
        except Exception as e:
            feedback.append(f"Error during VLM check: {str(e)}")
        finally:
            if os.path.exists(temp_plot.name):
                os.unlink(temp_plot.name)
    elif plot_exists and not query_vlm:
        # Fallback if VLM tool is missing
        score += 35
        feedback.append("VLM unavailable, assuming plot is valid based on file attributes.")

    # ---------------------------------------------------------
    # Final Score Calculation
    # ---------------------------------------------------------
    # Pass if score >= 60 AND critical model check passed
    passed = (score >= 60) and model_passed
    
    if not model_passed:
        feedback.append("CRITICAL FAIL: The split-plot statistical model was incorrect.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }