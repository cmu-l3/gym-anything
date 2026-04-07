#!/usr/bin/env python3
"""
Verifier for mauna_loa_co2_analysis_html task.

Checks:
1. Python script exists and contains logic to read the CSV (anti-gaming).
2. HTML file exists and contains the correct decadal averages.
3. HTML file contains the correct max jump year (2016).
4. Sugar Journal contains an entry titled "Mauna Loa CO2 Report".
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mauna_loa_co2_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/co2_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    script_content = result.get('script_content', '')
    html_text = result.get('html_text', '')
    
    # 1. Verify Python Script (15 points)
    if result.get('script_exists'):
        # Check that it actually accesses the file (prevents hallucinating HTML directly without parsing)
        if "co2_data.csv" in script_content and "open" in script_content:
            score += 15
            feedback.append("Python script reads CSV data")
        else:
            feedback.append("Python script exists but lacks CSV file I/O logic")
    else:
        feedback.append("Python script analyze_co2.py not found")

    # 2. Verify HTML Output & Mathematics (65 points total)
    if result.get('html_exists'):
        score += 10
        feedback.append("HTML report generated")

        # Check 1980s average: ~345.56 (allow 345.5 or 345.6)
        if re.search(r'345\.[56]', html_text):
            score += 10
            feedback.append("1980s average correct")
        else:
            feedback.append("1980s average missing/incorrect")

        # Check 1990s average: ~360.43 (allow 360.4)
        if re.search(r'360\.4', html_text):
            score += 10
            feedback.append("1990s average correct")
        else:
            feedback.append("1990s average missing/incorrect")

        # Check 2000s average: ~378.56 (allow 378.5 or 378.6)
        if re.search(r'378\.[56]', html_text):
            score += 10
            feedback.append("2000s average correct")
        else:
            feedback.append("2000s average missing/incorrect")

        # Check 2010s average: ~400.20 (allow 400.1 or 400.2)
        if re.search(r'400\.[12]', html_text):
            score += 10
            feedback.append("2010s average correct")
        else:
            feedback.append("2010s average missing/incorrect")

        # Check max jump year: 2016
        if "2016" in html_text:
            score += 15
            feedback.append("Max jump year correct (2016)")
        else:
            feedback.append("Max jump year missing/incorrect")
    else:
        feedback.append("HTML report co2_report.html not found")

    # 3. Verify Journal Integration (20 points)
    if result.get('journal_found'):
        score += 20
        feedback.append("Journal entry 'Mauna Loa CO2 Report' found")
    else:
        feedback.append("Journal entry 'Mauna Loa CO2 Report' not found")

    # Threshold for passing is 75 points
    passed = score >= 75
    
    if passed:
        feedback.insert(0, "SUCCESS")
    else:
        feedback.insert(0, "FAILED")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_logic": "co2_data.csv" in script_content and "open" in script_content,
            "html_exists": result.get('html_exists', False),
            "journal_found": result.get('journal_found', False)
        }
    }