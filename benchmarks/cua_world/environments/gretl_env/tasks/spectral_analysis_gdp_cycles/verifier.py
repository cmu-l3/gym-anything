#!/usr/bin/env python3
"""
Verifier for spectral_analysis_gdp_cycles task.

Verification Logic:
1. Files Existence & Anti-gaming: Checks if files were created during task.
2. Data Validation (Key Econometric Check):
   - Parses the periodogram data file.
   - Checks if the spectral density values imply stationary data (growth rate) vs non-stationary (raw levels).
   - Raw GDP periodogram has massive values at frequency ~0.
   - Growth rate periodogram has much smaller values spread across frequencies.
3. Visualization: Checks if plot file exists and has content.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spectral_analysis_gdp_cycles(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 1. Check Data File Existence & Timestamp (30 pts)
    if result.get('data_exists', False):
        if result.get('data_created_during_task', False):
            score += 30
            feedback.append("Data file created successfully.")
        else:
            score += 10
            feedback.append("Data file exists but timestamp is old (reused?).")
    else:
        feedback.append("Data file output not found.")

    # 2. Check Plot File Existence (20 pts)
    if result.get('plot_exists', False) and result.get('plot_size_bytes', 0) > 1000:
        if result.get('plot_created_during_task', False):
            score += 20
            feedback.append("Plot file created successfully.")
        else:
            score += 10
            feedback.append("Plot file exists but timestamp is old.")
    else:
        feedback.append("Plot file output not found or empty.")

    # 3. Content Verification (50 pts)
    # We need to analyze the numbers in the text file to ensure they differenced the data.
    content_passed = False
    
    if result.get('data_exists', False):
        temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            # Copy the actual data file from the environment
            copy_from_env("/home/ga/Documents/gretl_output/periodogram_data.txt", temp_data.name)
            
            with open(temp_data.name, 'r') as f:
                lines = f.readlines()
            
            # Parse Gretl spectral output
            # Usually format: "Frequency   Spectrum" or similar headers
            # Skip headers, find numeric lines
            max_spectrum = 0.0
            valid_lines = 0
            
            for line in lines:
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        val = float(parts[1])
                        # Keep track of max value
                        if val > max_spectrum:
                            max_spectrum = val
                        valid_lines += 1
                    except ValueError:
                        continue
            
            if valid_lines > 10:
                # CRITICAL ECONOMETRIC CHECK:
                # Raw GDP (levels) is non-stationary. The periodogram at low freq (near 0)
                # will be massive. For US GDP ~10000-14000, variance is huge.
                # Spectrum peak for levels often > 10^5 or 10^6 depending on normalization.
                #
                # Growth rate (log diff) is approx 0.005-0.01. Variance is tiny.
                # Spectrum peak should be small (typically < 1.0 or < 10.0 depending on N).
                
                # Threshold: If max spectrum > 1000, they likely used raw GDP.
                if max_spectrum > 1000:
                    feedback.append(f"Data Validation FAILED: Spectral density values are extremely high (Max: {max_spectrum:.2f}). This indicates analysis of raw non-stationary GDP, not the growth rate.")
                elif max_spectrum == 0:
                    feedback.append("Data Validation FAILED: Spectral values are all zero.")
                else:
                    score += 50
                    content_passed = True
                    feedback.append(f"Data Validation PASSED: Spectral density values (Max: {max_spectrum:.4f}) are consistent with a stationary growth rate series.")
            else:
                feedback.append("Data Validation FAILED: Could not parse sufficient data rows.")

        except Exception as e:
            feedback.append(f"Data Validation ERROR: {str(e)}")
        finally:
            if os.path.exists(temp_data.name):
                os.unlink(temp_data.name)

    passed = (score >= 80) and content_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }