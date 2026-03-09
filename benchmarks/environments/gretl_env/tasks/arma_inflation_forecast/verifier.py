#!/usr/bin/env python3
"""
Verifier for ARMA Inflation Forecast task.

Verifies:
1. Script existence and content (syntax check).
2. Output file existence.
3. Numerical accuracy of coefficients and forecasts compared to Ground Truth.
4. Anti-gaming (timestamps).
"""

import json
import os
import re
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_arma_inflation_forecast(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define score components
    score = 0
    feedback = []
    
    # Files to retrieve
    files_to_copy = {
        "result_json": "/tmp/task_result.json",
        "reference_json": "/tmp/reference_values.json",
        "agent_script": "/home/ga/Documents/gretl_output/inflation_forecast.inp",
        "agent_output": "/home/ga/Documents/gretl_output/inflation_forecast_output.txt"
    }
    
    local_files = {}
    
    # 1. Copy files from container
    with tempfile.TemporaryDirectory() as temp_dir:
        for name, remote_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {name} from {remote_path}: {e}")
                local_files[name] = None

        # Load Metadata
        if not local_files["result_json"] or not os.path.exists(local_files["result_json"]):
            return {"passed": False, "score": 0, "feedback": "Task result file missing."}
            
        with open(local_files["result_json"], 'r') as f:
            task_result = json.load(f)

        # Load Reference Values
        ref_values = {}
        if local_files["reference_json"] and os.path.exists(local_files["reference_json"]):
            try:
                with open(local_files["reference_json"], 'r') as f:
                    ref_values = json.load(f)
            except:
                feedback.append("Warning: Could not load reference values.")
        
        # --- CRITERION 1: Script File (30 pts) ---
        script_info = task_result.get("script_file", {})
        if script_info.get("exists") and script_info.get("size") > 0:
            score += 10
            feedback.append("Script file created.")
            
            if script_info.get("created_during_task"):
                score += 5
                feedback.append("Script created during task (timestamp verified).")
            else:
                feedback.append("Warning: Script timestamp predates task start.")

            # Check content
            if local_files["agent_script"]:
                with open(local_files["agent_script"], 'r') as f:
                    content = f.read().lower()
                    
                # Check for key commands
                if "smpl" in content and ("1984" in content or "2008" in content):
                    score += 5
                    feedback.append("Script contains sample restriction.")
                else:
                    feedback.append("Missing or incorrect 'smpl' command.")

                if "arma" in content or "arima" in content:
                    score += 5
                    feedback.append("Script contains ARMA/ARIMA command.")
                else:
                    feedback.append("Missing 'arma' command.")
                    
                if "fcast" in content:
                    score += 5
                    feedback.append("Script contains forecast command.")
                else:
                    feedback.append("Missing 'fcast' command.")
        else:
            feedback.append("Script file not found or empty.")

        # --- CRITERION 2: Output File & Model Accuracy (40 pts) ---
        output_info = task_result.get("output_file", {})
        if output_info.get("exists") and output_info.get("size") > 0:
            score += 10
            feedback.append("Output file created.")
            
            if local_files["agent_output"]:
                with open(local_files["agent_output"], 'r') as f:
                    out_content = f.read()
                
                # Parse output for coefficients
                # Regex for "phi_1      0.12345" or similar standard gretl output
                # Gretl output format often looks like:
                # const       1.234   ...
                # phi_1       0.567   ...
                # theta_1    -0.890   ...
                
                # Helper to find float after key string
                def find_coeff(text, key):
                    # Look for key, optional whitespace, numbers
                    # Case insensitive search
                    match = re.search(rf"{key}\s+([+-]?\d+\.\d+)", text, re.IGNORECASE)
                    if match:
                        return float(match.group(1))
                    return None

                agent_phi = find_coeff(out_content, "phi_?1")
                agent_theta = find_coeff(out_content, "theta_?1")
                
                # Check against reference
                ref_phi = ref_values.get("phi_1")
                ref_theta = ref_values.get("theta_1")
                
                tolerance_coeff = 0.05
                
                if agent_phi is not None and ref_phi is not None:
                    if abs(agent_phi - ref_phi) < tolerance_coeff:
                        score += 10
                        feedback.append(f"AR(1) coefficient correct ({agent_phi}).")
                    else:
                        feedback.append(f"AR(1) coefficient mismatch (Got {agent_phi}, Expected {ref_phi}).")
                elif agent_phi is None:
                    feedback.append("Could not parse AR(1) coefficient from output.")

                if agent_theta is not None and ref_theta is not None:
                    if abs(agent_theta - ref_theta) < tolerance_coeff:
                        score += 10
                        feedback.append(f"MA(1) coefficient correct ({agent_theta}).")
                    else:
                        feedback.append(f"MA(1) coefficient mismatch (Got {agent_theta}, Expected {ref_theta}).")
                
                # Check for sample info in output
                if "2008:4" in out_content or "2008:04" in out_content or "100" in out_content: # 100 obs roughly
                    score += 10
                    feedback.append("Output reflects correct estimation sample.")

        else:
            feedback.append("Output file not found or empty.")

        # --- CRITERION 3: Forecast Values (30 pts) ---
        # Look for the specific forecast values for 2009
        # Gretl 'fcast' output often lists:
        # Obs     Forecast ...
        # 2009:1   2.1234
        if local_files["agent_output"] and output_info.get("exists"):
            with open(local_files["agent_output"], 'r') as f:
                out_content = f.read()

            forecast_found = 0
            
            # Try to match the 3 forecast periods
            # Reference keys: f_2009_1, f_2009_2, f_2009_3
            periods = [("2009:1", "f_2009_1"), ("2009:2", "f_2009_2"), ("2009:3", "f_2009_3")]
            
            for date_str, ref_key in periods:
                ref_val = ref_values.get(ref_key)
                if ref_val is None: continue
                
                # Regex: Date string followed by float
                match = re.search(rf"{date_str}\s+([+-]?\d+\.\d+)", out_content)
                if match:
                    agent_val = float(match.group(1))
                    if abs(agent_val - ref_val) < 1.0: # Generous tolerance for forecast
                        forecast_found += 1
                else:
                    # Alternative format check (raw numbers printed)
                    pass

            if forecast_found >= 3:
                score += 30
                feedback.append("All 3 forecast periods found and accurate.")
            elif forecast_found > 0:
                score += 10 * forecast_found
                feedback.append(f"Found {forecast_found}/3 accurate forecast values.")
            else:
                feedback.append("Forecast values for 2009 not found or inaccurate.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }