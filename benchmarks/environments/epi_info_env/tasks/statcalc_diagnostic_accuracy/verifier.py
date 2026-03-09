#!/usr/bin/env python3
"""
Verifier for statcalc_diagnostic_accuracy task.

Metric: Check if diagnostic_report.txt contains correct Sensitivity, Specificity, PPV, NPV values.
Values are derived from:
- TP=180, FN=20, FP=40, TN=760
- Prevalence change from calculated baseline to 2.0%
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_statcalc_diagnostic_accuracy(traj, env_info, task_info):
    """
    Verify the diagnostic accuracy task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "Sensitivity": 90.0,
        "Specificity": 95.0,
        "Baseline_PPV": 81.8,
        "Baseline_NPV": 97.4,
        "Airport_PPV_at_2_percent": 26.9
    })
    tolerance = metadata.get('tolerance', 0.2)

    # Copy result JSON from container (Windows path mapped to temp file)
    # The export script saves to C:\Users\Docker\AppData\Local\Temp\task_result.json
    # In 'epi_info_env', we assume standard mapping or ability to copy from that path.
    # Note: copy_from_env path must match what's in the container.
    
    # Path in container (as written by export_result.ps1)
    container_result_path = "C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(container_result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extraction Checks
    output_exists = result_data.get('output_exists', False)
    file_content = result_data.get('file_content', "")
    file_created_fresh = result_data.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not file_created_fresh:
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task window."}

    # Parse the content
    # Expected format lines like "Key: Value%"
    # Regex to capture floats
    parsed_values = {}
    
    # Helper to find value for a key
    def find_value(key_pattern, text):
        # Matches "Key: 90.0%" or "Key: 90.0"
        regex = re.compile(rf"{key_pattern}.*?([\d\.]+)", re.IGNORECASE)
        match = regex.search(text)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                return None
        return None

    parsed_values['Sensitivity'] = find_value("Sensitivity", file_content)
    parsed_values['Specificity'] = find_value("Specificity", file_content)
    parsed_values['Baseline_PPV'] = find_value("Baseline_PPV", file_content)
    parsed_values['Baseline_NPV'] = find_value("Baseline_NPV", file_content)
    parsed_values['Airport_PPV_at_2_percent'] = find_value("Airport_PPV", file_content)

    # Scoring
    score = 0
    feedback_lines = []
    
    # 1. File Existence & Freshness (10 pts)
    score += 10
    feedback_lines.append("File created successfully.")

    # 2. Check Values (90 pts distributed)
    # Sensitivity (20)
    if parsed_values['Sensitivity'] is not None and abs(parsed_values['Sensitivity'] - expected['Sensitivity']) <= tolerance:
        score += 20
        feedback_lines.append(f"Sensitivity correct ({parsed_values['Sensitivity']}%).")
    else:
        feedback_lines.append(f"Sensitivity incorrect or missing. Found: {parsed_values.get('Sensitivity')}, Expected: {expected['Sensitivity']}")

    # Specificity (20)
    if parsed_values['Specificity'] is not None and abs(parsed_values['Specificity'] - expected['Specificity']) <= tolerance:
        score += 20
        feedback_lines.append(f"Specificity correct ({parsed_values['Specificity']}%).")
    else:
        feedback_lines.append(f"Specificity incorrect or missing. Found: {parsed_values.get('Specificity')}, Expected: {expected['Specificity']}")

    # Baseline PPV (15)
    if parsed_values['Baseline_PPV'] is not None and abs(parsed_values['Baseline_PPV'] - expected['Baseline_PPV']) <= tolerance:
        score += 15
        feedback_lines.append(f"Baseline PPV correct ({parsed_values['Baseline_PPV']}%).")
    else:
        feedback_lines.append(f"Baseline PPV incorrect or missing. Found: {parsed_values.get('Baseline_PPV')}, Expected: {expected['Baseline_PPV']}")

    # Baseline NPV (15)
    if parsed_values['Baseline_NPV'] is not None and abs(parsed_values['Baseline_NPV'] - expected['Baseline_NPV']) <= tolerance:
        score += 15
        feedback_lines.append(f"Baseline NPV correct ({parsed_values['Baseline_NPV']}%).")
    else:
        feedback_lines.append(f"Baseline NPV incorrect or missing. Found: {parsed_values.get('Baseline_NPV')}, Expected: {expected['Baseline_NPV']}")

    # Adjusted PPV (20) - Critical for task logic
    if parsed_values['Airport_PPV_at_2_percent'] is not None and abs(parsed_values['Airport_PPV_at_2_percent'] - expected['Airport_PPV_at_2_percent']) <= tolerance:
        score += 20
        feedback_lines.append(f"Airport PPV correct ({parsed_values['Airport_PPV_at_2_percent']}%).")
    else:
        feedback_lines.append(f"Airport PPV incorrect or missing. Found: {parsed_values.get('Airport_PPV_at_2_percent')}, Expected: {expected['Airport_PPV_at_2_percent']}")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_lines)
    }