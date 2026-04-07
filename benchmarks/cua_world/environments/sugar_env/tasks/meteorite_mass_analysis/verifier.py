#!/usr/bin/env python3
"""
Verifier for meteorite_mass_analysis task.

Checks that:
1. The agent wrote a Python script (meteorite_analyzer.py).
2. The agent produced an output file (top_10_meteorites.txt).
3. The output contains the correct top meteorites (Hoba, Campo del Cielo, Cape York).
4. The output matches the 1-10 ranking format.
5. The output correctly calculates the average mass of valid entries.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_meteorite_mass_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/meteorite_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Expected Values
    EXPECTED_AVERAGE = 21653608.81
    TOP_3 = ["Hoba", "Campo del Cielo", "Cape York"]

    output_exists = result.get('output_exists', False)
    output_modified = result.get('output_modified', False)
    output_content = result.get('output_content', "")
    
    script_exists = result.get('script_exists', False)
    script_size = result.get('script_size', 0)
    script_modified = result.get('script_modified', False)

    # Criterion 1: Script exists and is valid (10 pts)
    if script_exists and script_size > 50 and script_modified:
        score += 10
        feedback.append("Valid Python script created.")
    elif script_exists:
        score += 5
        feedback.append("Python script found but may be empty or pre-existing.")
    else:
        feedback.append("Missing meteorite_analyzer.py script.")

    # Criterion 2: Output file exists (10 pts)
    if output_exists and output_modified:
        score += 10
        feedback.append("Output text file created.")
    elif output_exists:
        score += 5
        feedback.append("Output text file found but timestamp indicates it might be old.")
    else:
        feedback.append("Missing top_10_meteorites.txt file.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3-5: Top 3 Meteorites Identified (35 pts total)
    if "Hoba" in output_content:
        score += 15
        feedback.append("Heaviest meteorite (Hoba) found in output.")
    else:
        feedback.append("Missing Hoba in output.")

    if "Campo del Cielo" in output_content:
        score += 10
        feedback.append("Campo del Cielo found.")
        
    if "Cape York" in output_content:
        score += 10
        feedback.append("Cape York found.")

    # Criterion 6: Ranked Format (15 pts)
    # Check if lines starting with "1." up to "10." exist.
    has_ranking = True
    for i in range(1, 11):
        if not re.search(rf'\b{i}\.\s+', output_content):
            has_ranking = False
            break
            
    if has_ranking:
        score += 15
        feedback.append("1-10 ranking format verified.")
    else:
        feedback.append("1-10 numerical ranking format incomplete or missing.")

    # Criterion 7: Average Mass Calculation (20 pts for exact, 10 for close)
    # Looking for "Average Mass: <value>" 
    # Handle optional commas and optional trailing 'g'
    match = re.search(r'Average Mass:\s*([\d\,\.]+)', output_content, re.IGNORECASE)
    if match:
        extracted_val_str = match.group(1).replace(',', '')
        try:
            extracted_val = float(extracted_val_str)
            diff = abs(extracted_val - EXPECTED_AVERAGE)
            
            if diff < 0.05:
                # Exact match (accounting for floating point differences)
                score += 20
                feedback.append(f"Average mass perfectly calculated ({extracted_val_str}).")
            elif diff < 1.0:
                # Rounded to whole number or 1 decimal
                score += 15
                feedback.append(f"Average mass very close ({extracted_val_str}), but slight rounding difference.")
            elif diff < 1000.0:
                # Slightly off, maybe included missing values incorrectly
                score += 5
                feedback.append(f"Average mass calculated but off by a margin ({extracted_val_str}).")
            else:
                feedback.append(f"Average mass calculated ({extracted_val_str}) but incorrect (expected ~{EXPECTED_AVERAGE}).")
        except ValueError:
            feedback.append("Could not parse average mass value as a number.")
    else:
        feedback.append("Average Mass line not found or incorrectly formatted.")

    # Final pass threshold: score >= 70, must have created output, must have Hoba.
    passed = (score >= 70 and output_exists and "Hoba" in output_content)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": script_exists,
            "output_exists": output_exists,
            "has_hoba": "Hoba" in output_content
        }
    }