#!/usr/bin/env python3
"""
Verifier for import_time_series_csv task.

Verifies:
1. GDT file creation and validity (XML parsing)
2. Time series structure (Frequency = Quarterly, Start = 1984:1)
3. Variable existence (gdp, inf)
4. Plot creation
"""

import json
import os
import sys
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_time_series_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gdt = metadata.get('expected_gdt_path', '/home/ga/Documents/gretl_output/us_macro_ts.gdt')
    
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Retrieve Result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # 2. Verify GDT File Existence (20 pts)
    if not result.get('gdt_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Gretl data file (.gdt) was not saved to the expected location."
        }
    
    score += 20
    feedback.append("GDT file created (+20)")

    # 3. Retrieve and Parse GDT File
    # Gretl .gdt files are XML. We parse them to check structure.
    try:
        temp_gdt = tempfile.NamedTemporaryFile(delete=False, suffix='.gdt')
        copy_from_env(expected_gdt, temp_gdt.name)
        
        tree = ET.parse(temp_gdt.name)
        root = tree.getroot()
        os.unlink(temp_gdt.name)
        
        # Check Frequency (30 pts)
        # Expected: frequency="4"
        freq = root.get('frequency')
        if freq == '4':
            score += 30
            feedback.append("Frequency correctly set to Quarterly (+30)")
        else:
            feedback.append(f"Incorrect frequency: found '{freq}', expected '4' (Quarterly)")

        # Check Start Observation (30 pts)
        # Expected: startobs="1984:1"
        start_obs = root.get('startobs')
        if start_obs == '1984:1':
            score += 30
            feedback.append("Start date correctly set to 1984:1 (+30)")
        else:
            feedback.append(f"Incorrect start date: found '{start_obs}', expected '1984:1'")

        # Check Variables (10 pts)
        # Look for <variable name="gdp"> etc.
        vars_found = [v.get('name') for v in root.findall(".//variable")]
        required_vars = ['gdp', 'inf']
        missing = [v for v in required_vars if v not in vars_found]
        
        if not missing:
            score += 10
            feedback.append("All variables (gdp, inf) found (+10)")
        else:
            feedback.append(f"Missing variables: {missing}")

    except ET.ParseError:
        feedback.append("Error: Saved file is not a valid Gretl XML/GDT file.")
    except Exception as e:
        feedback.append(f"Error verifying GDT file content: {str(e)}")

    # 4. Verify Plot Existence (10 pts)
    if result.get('plot_exists', False):
        score += 10
        feedback.append("GDP plot created (+10)")
    else:
        feedback.append("GDP plot not found (-10)")

    # Pass logic: Must have correct frequency and start date
    passed = (score >= 80) and ("Incorrect frequency" not in str(feedback)) and ("Incorrect start date" not in str(feedback))

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }