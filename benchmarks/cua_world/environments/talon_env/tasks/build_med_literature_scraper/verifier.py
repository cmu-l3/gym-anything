#!/usr/bin/env python3
"""
Verifier for build_med_literature_scraper task.
Relies on robust programmatic analysis of the agent's implemented Python logic via a test runner context inside the container.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_med_scraper(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Retrieve the evaluation output constructed by export_result.ps1
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Directory/Files (10 points)
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    if py_exists and talon_exists:
        score += 10
        feedback.append("Module files exist")
    else:
        feedback.append("Missing .py or .talon file")

    # 2. Talon Command Syntax (20 points)
    talon_content = result.get('talon_content', '').lower()
    if 'scrape identifiers' in talon_content and ('scrape_literature_ids' in talon_content or 'user.' in talon_content):
        score += 20
        feedback.append("Talon command syntax is valid")
    elif 'scrape identifiers' in talon_content:
        score += 10
        feedback.append("Talon command declared but action call is unclear")

    # 3. Python Action Implementation (20 points)
    test_exec = result.get('test_execution', {})
    func_found = test_exec.get('func_found', False)
    if func_found:
        score += 20
        feedback.append("Python action correctly registered")
    else:
        err = test_exec.get('error', '')
        feedback.append(f"Python function not found or failed to load: {err[:80]}")

    # Regex tests - evaluating the agent's logic on a hidden test string
    csv_content = test_exec.get('test_csv_content', '')
    
    # 4. Regex PMIDs (15 points)
    # Hidden string expected: 98765432, invalid string expected to avoid: 1234567890
    if '98765432' in csv_content and '1234567890' not in csv_content:
        score += 15
        feedback.append("PMID regex correctly isolated standard lengths")
    elif '98765432' in csv_content:
        score += 7
        feedback.append("PMID regex captured but lacked valid length boundaries")

    # 5. Regex DOIs (15 points)
    # Hidden string expected: 10.1136/bmj.m1234
    if '10.1136/bmj.m1234' in csv_content:
        score += 15
        feedback.append("DOI regex properly extracted")

    # 6. Regex NCTs (10 points)
    # Hidden string expected: NCT99887766
    if 'NCT99887766' in csv_content or 'nct99887766' in csv_content.lower():
        score += 10
        feedback.append("NCT regex properly extracted")

    # 7. CSV Format Checks (10 points)
    lines = [line for line in csv_content.split('\n') if line.strip()]
    well_formatted = len(lines) > 0
    for line in lines:
        if ',' not in line or len(line.split(',')) != 2:
            well_formatted = False
            break

    if well_formatted and func_found and lines:
        score += 10
        feedback.append("CSV output is perfectly formatted as Type,Value")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }