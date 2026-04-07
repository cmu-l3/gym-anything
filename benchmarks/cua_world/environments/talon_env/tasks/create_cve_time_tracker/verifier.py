#!/usr/bin/env python3
"""
Verifier for create_cve_time_tracker task.

Verification Strategy (Multi-Signal Anti-Gaming):
1. Static File Verification: Checks directory structure and basic code contents.
2. Dynamic Action Verification: Relies on the injected post-task `dynamic_cve_tester.py`
   to trigger the agent's Talon actions, evaluating whether the agent correctly
   managed internal module state and wrote the expected outputs to the CSV file.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cve_time_tracker(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch results exported by export_result.ps1
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')
    csv_exists = result.get('csv_exists', False)
    csv_content = result.get('csv_content', '')

    # CRITERION 1: File Structure (10 points)
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("File structure correct")
    else:
        feedback_parts.append("Missing .py or .talon files")

    # CRITERION 2: Data Loading (15 points)
    if "cisa_kev.csv" in py_content or "cisa" in py_content.lower():
        score += 15
        feedback_parts.append("Data loading code detected")
    else:
        feedback_parts.append("No CISA dataset reading found in Python")

    # CRITERION 3: Voice Commands (15 points)
    if "investigate vulnerability" in talon_content.lower() and "stop investigation" in talon_content.lower():
        score += 15
        feedback_parts.append("Voice commands properly mapped")
    else:
        feedback_parts.append("Missing required voice command mappings")

    # CRITERION 4, 5, 6: State Management, Validation Logic, and Output Logging (60 points total)
    valid_cve_logged = False
    fake_cve_logged = False
    format_correct = False
    duration_correct = False
    
    if csv_exists and csv_content:
        lines = [line.strip() for line in csv_content.split('\n') if line.strip()]
        
        for line in lines:
            parts = line.split(',')
            
            # Look for the dynamically injected fake CVE
            if "CVE-9999-99999" in line:
                fake_cve_logged = True
                
            # Look for the dynamically injected valid CVE
            if "CVE-2021-44228" in line.upper():
                valid_cve_logged = True
                
                # Format Verification (20 points): YYYY-MM-DD,CVE_ID,DurationSeconds
                if len(parts) >= 3:
                    date_part, cve_part, duration_part = parts[0], parts[1], parts[2]
                    
                    if date_part.startswith("202") and "CVE-2021-44228" in cve_part:
                        format_correct = True
                    
                    # State Management Verification (20 points): Duration should be ~2s
                    try:
                        duration = float(duration_part)
                        if 1.0 <= duration <= 4.0:
                            duration_correct = True
                    except ValueError:
                        pass

    # Assigning Dynamic Test Scores
    if valid_cve_logged and format_correct:
        score += 20
        feedback_parts.append("Output formatting correct")
    elif valid_cve_logged:
        score += 10
        feedback_parts.append("Output written but formatting imperfect")
    else:
        feedback_parts.append("Valid CVE was not logged")

    if duration_correct:
        score += 20
        feedback_parts.append("Timer state tracking correct (~2s)")
    elif valid_cve_logged:
        feedback_parts.append("Timer duration incorrect")

    if not fake_cve_logged and valid_cve_logged:
        score += 20
        feedback_parts.append("Validation logic successfully rejected fake CVE")
    elif fake_cve_logged:
        feedback_parts.append("Validation logic FAILED (logged fake CVE)")

    # Final Evaluation
    key_criteria_met = valid_cve_logged and not fake_cve_logged and py_exists
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }