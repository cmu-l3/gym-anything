#!/usr/bin/env python3
"""
Verifier for compare_fixed_vs_variable_aep task.

Checks:
1. Output files exist and were created during task.
2. Fixed speed file shows constant RPM.
3. Variable speed file shows varying RPM.
4. Data content is valid (Power vs Windspeed).
"""

import json
import os
import tempfile
import numpy as np
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_qblade_export(filepath):
    """
    Parses a QBlade export file.
    Expects whitespace or comma separated values.
    Returns a dict with columns.
    """
    data = {}
    headers = []
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        
        # Find header line (usually starts with something meaningful or is the first non-comment)
        start_idx = 0
        for i, line in enumerate(lines):
            # QBlade exports often have a header line like: "Windspeed [m/s] Power [W] ..."
            # We look for a line with at least 3 distinct word tokens
            parts = line.strip().replace(',', ' ').split()
            if len(parts) > 2 and any(k in line.lower() for k in ['wind', 'power', 'rpm', 'speed', 'rot']):
                headers = parts
                start_idx = i + 1
                break
        
        if not headers:
            # Fallback: assume standard columns if no header found
            # But QBlade usually provides headers. If not found, return empty.
            return None

        # Normalize headers to simple keys
        normalized_headers = []
        for h in headers:
            h_lower = h.lower()
            if 'wind' in h_lower: normalized_headers.append('wind')
            elif 'power' in h_lower and 'coeff' not in h_lower: normalized_headers.append('power')
            elif 'rpm' in h_lower or 'rot' in h_lower: normalized_headers.append('rpm')
            else: normalized_headers.append('other')

        # Parse data
        parsed_data = {k: [] for k in set(normalized_headers) if k != 'other'}
        
        for line in lines[start_idx:]:
            parts = line.strip().replace(',', ' ').split()
            if len(parts) != len(headers):
                continue
            try:
                # Map values to normalized headers
                for h_norm, val in zip(normalized_headers, parts):
                    if h_norm != 'other':
                        parsed_data[h_norm].append(float(val))
            except ValueError:
                continue
                
        return parsed_data
    except Exception as e:
        logger.error(f"Error parsing file {filepath}: {e}")
        return None

def verify_compare_fixed_vs_variable_aep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Get result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    score = 0
    feedback = []
    
    # Check if app was running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback.append("QBlade was running.")
    else:
        feedback.append("QBlade was not running.")

    # Files to verify
    files_to_check = [
        ('fixed', result.get('fixed_file_path'), result.get('fixed_file_created_during_task')),
        ('variable', result.get('variable_file_path'), result.get('variable_file_created_during_task'))
    ]

    data_contents = {}

    for label, path, created in files_to_check:
        if not path or not created:
            feedback.append(f"{label.capitalize()} output file not created during task.")
            continue
            
        score += 10 # 10 pts for creation
        
        # Copy file content
        temp_data_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(path, temp_data_file.name)
            parsed = parse_qblade_export(temp_data_file.name)
            
            if parsed and 'rpm' in parsed and 'power' in parsed and len(parsed['rpm']) > 3:
                score += 10 # 10 pts for valid content format
                data_contents[label] = parsed
                feedback.append(f"Valid data found in {label} file.")
            else:
                feedback.append(f"{label.capitalize()} file unreadable or missing columns (RPM/Power).")
        except Exception as e:
            feedback.append(f"Error processing {label} file: {e}")
        finally:
            if os.path.exists(temp_data_file.name):
                os.unlink(temp_data_file.name)

    # Analyze Physics
    physics_passed = False
    
    if 'fixed' in data_contents:
        rpms = np.array(data_contents['fixed']['rpm'])
        std_dev = np.std(rpms)
        # Fixed speed should have very low variance (allowing for slight solver noise)
        if std_dev < 1.0: 
            score += 25
            feedback.append("Fixed speed simulation confirmed (Constant RPM).")
        else:
            feedback.append(f"Fixed speed check failed: RPM varied (std dev: {std_dev:.2f}).")

    if 'variable' in data_contents:
        rpms = np.array(data_contents['variable']['rpm'])
        std_dev = np.std(rpms)
        # Variable speed should vary significantly over a 3-25m/s range
        if std_dev > 2.0:
            score += 25
            feedback.append("Variable speed simulation confirmed (Varying RPM).")
            physics_passed = True
        else:
            feedback.append(f"Variable speed check failed: RPM did not vary significantly (std dev: {std_dev:.2f}).")

    passed = score >= 75 and physics_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }