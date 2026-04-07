#!/usr/bin/env python3
"""Verifier for quantify_pv_heatwave_loss task.

Validates PySAM thermal loss simulation physics, output format, 
AND deeply inspects the modified CSV to ensure proper data wrangling.
"""

import json
import tempfile
import os
import csv
import math

def check_csv_wrangling(copy_from_env):
    """
    Copies the baseline and heatwave CSV files and deeply verifies:
    1. 2-row header is preserved.
    2. July (Month 7) temperatures are +10 C higher.
    3. Other months' temperatures are identical.
    """
    baseline_path = "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
    heatwave_path = "/home/ga/SAM_Weather_Data/phoenix_heatwave.csv"
    
    temp_baseline = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_heatwave = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(baseline_path, temp_baseline.name)
        copy_from_env(heatwave_path, temp_heatwave.name)
        
        with open(temp_baseline.name, 'r', encoding='utf-8') as fb, open(temp_heatwave.name, 'r', encoding='utf-8') as fh:
            rows_b = list(csv.reader(fb))
            rows_h = list(csv.reader(fh))
            
        if len(rows_b) != len(rows_h):
            return False, "Row count mismatch between baseline and heatwave CSV."
        
        if len(rows_b) < 8760:
            return False, "CSV file is too short to be a valid annual weather file."
            
        # Check header rows (first 2 rows)
        if rows_b[0] != rows_h[0]:
            return False, "First header row (metadata) was modified or missing."
            
        # Identify columns from the second row
        header = [x.lower().strip() for x in rows_b[1]]
        month_idx = None
        tdry_idx = None
        
        for i, h in enumerate(header):
            if h in ['month', 'mo']:
                month_idx = i
            elif h in ['tdry', 'temp', 'temperature', 't_dry', 'tdry (\'c\')', 'tdry (c)']:
                tdry_idx = i
                
        if month_idx is None or tdry_idx is None:
            return False, "Could not identify 'Month' or 'Tdry' columns in the baseline CSV header."
            
        # Verify the data manipulation
        july_checked = 0
        other_checked = 0
        
        for i in range(2, len(rows_b)):
            try:
                month = int(float(rows_b[i][month_idx]))
                temp_b = float(rows_b[i][tdry_idx])
                temp_h = float(rows_h[i][tdry_idx])
            except (ValueError, IndexError):
                continue
                
            if month == 7:
                expected_temp = temp_b + 10.0
                if abs(temp_h - expected_temp) > 0.1:
                    return False, f"July temp mismatch at row {i+1}: expected {expected_temp}, got {temp_h}"
                july_checked += 1
            else:
                if abs(temp_h - temp_b) > 0.1:
                    return False, f"Non-July temp improperly modified at row {i+1}: baseline {temp_b}, heatwave {temp_h}"
                other_checked += 1
                
        if july_checked == 0:
            return False, "No July (Month 7) rows found in the CSV to verify."
            
        return True, f"Data wrangling correct (verified {july_checked} July rows, {other_checked} other rows)."
        
    except Exception as e:
        return False, f"Error inspecting CSV files: {str(e)}"
    finally:
        if os.path.exists(temp_baseline.name):
            os.unlink(temp_baseline.name)
        if os.path.exists(temp_heatwave.name):
            os.unlink(temp_heatwave.name)


def verify_quantify_pv_heatwave_loss(traj, env_info, task_info):
    """Verify heatwave PV simulation and data manipulation was completed successfully.

    Scoring: 100 points max
    - File Existence (15 pts)
    - Data Wrangling (25 pts)
    - Simulation Output JSON keys valid (20 pts)
    - Physical Validity of Yield (25 pts)
    - Math Accuracy (15 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_loss_pct = metadata.get('min_loss_pct', 3.0)
    max_loss_pct = metadata.get('max_loss_pct', 6.0)

    # 1. Read the framework's task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            sys_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read system result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check if files exist
    json_exists = sys_result.get('json_exists') is True or str(sys_result.get('json_exists')) == 'true'
    csv_exists = sys_result.get('csv_exists') is True or str(sys_result.get('csv_exists')) == 'true'
    json_mod = sys_result.get('json_modified') is True or str(sys_result.get('json_modified')) == 'true'
    csv_mod = sys_result.get('csv_modified') is True or str(sys_result.get('csv_modified')) == 'true'
    python_ran = sys_result.get('python_ran') is True or str(sys_result.get('python_ran')) == 'true'

    if not python_ran:
        feedback_parts.append("Warning: Python execution not detected.")

    if json_exists and csv_exists:
        points = 15
        if not json_mod or not csv_mod:
            points = 5
            feedback_parts.append("Files exist but were not created/modified during task.")
        else:
            feedback_parts.append("Output files generated.")
        score += points
    else:
        feedback_parts.append("Missing required output file(s).")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Check Data Wrangling (CSV Inspection)
    wrangling_pass, wrangling_msg = check_csv_wrangling(copy_from_env)
    if wrangling_pass:
        score += 25
        feedback_parts.append("CSV correctly modified (+10C in July).")
    else:
        feedback_parts.append(f"CSV Check Failed: {wrangling_msg}")
        # If they failed data wrangling, the simulation results will be garbage anyway
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Read agent's JSON output
    agent_json_path = "/home/ga/Documents/SAM_Projects/heatwave_impact.json"
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(agent_json_path, temp_agent.name)
        with open(temp_agent.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        feedback_parts.append("Failed to parse agent's output JSON.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)

    # 4. Check Simulation Output JSON
    required_keys = [
        'baseline_july_energy_kwh', 
        'heatwave_july_energy_kwh', 
        'july_absolute_loss_kwh', 
        'july_yield_loss_percent'
    ]
    
    missing_keys = [k for k in required_keys if k not in agent_data]
    if missing_keys:
        feedback_parts.append(f"JSON missing keys: {missing_keys}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    try:
        baseline = float(agent_data['baseline_july_energy_kwh'])
        heatwave = float(agent_data['heatwave_july_energy_kwh'])
        abs_loss = float(agent_data['july_absolute_loss_kwh'])
        pct_loss = float(agent_data['july_yield_loss_percent'])
    except ValueError:
        feedback_parts.append("JSON numerical fields contain non-numbers.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    if baseline > 0 and heatwave > 0:
        score += 20
        feedback_parts.append("Valid JSON outputs.")
    else:
        feedback_parts.append("Energy values must be > 0.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 5. Physical Validity
    if heatwave < baseline:
        score += 25
        feedback_parts.append("Physics correct: Heatwave reduced energy yield.")
    else:
        feedback_parts.append("Physics Error: Heatwave yield >= Baseline yield.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 6. Math Accuracy
    expected_abs_loss = baseline - heatwave
    expected_pct_loss = (expected_abs_loss / baseline) * 100 if baseline > 0 else 0
    
    math_correct = True
    if not math.isclose(abs_loss, expected_abs_loss, rel_tol=1e-3):
        math_correct = False
        feedback_parts.append(f"Math error in absolute loss: got {abs_loss}, expected {expected_abs_loss:.2f}.")
    if not math.isclose(pct_loss, expected_pct_loss, rel_tol=1e-3):
        math_correct = False
        feedback_parts.append(f"Math error in percentage loss: got {pct_loss}, expected {expected_pct_loss:.2f}.")

    if math_correct:
        if min_loss_pct <= pct_loss <= max_loss_pct:
            score += 15
            feedback_parts.append(f"Math correct and loss ({pct_loss:.2f}%) within physical bounds.")
        else:
            score += 5
            feedback_parts.append(f"Math correct, but loss ({pct_loss:.2f}%) outside expected physical range ({min_loss_pct}%-{max_loss_pct}%).")
            
    # Final pass determination
    # Key criteria: 
    # 1. Output files must be created (scored >= 5 from JSON check)
    # 2. CSV Wrangling must be exact (wrangling_pass is True)
    # 3. Physics check must pass (heatwave < baseline, granting the 25 points)
    key_criteria_met = wrangling_pass and (heatwave < baseline)
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }