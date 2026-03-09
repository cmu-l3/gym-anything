#!/usr/bin/env python3
"""
Verifier for Museum Conservation Chemical Hazard Audit.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_bool(value: str) -> bool:
    """Helper to parse boolean strings loosely."""
    v = str(value).strip().lower()
    return v in ('true', 'yes', '1', 't', 'y')

def parse_flash_point(value: str) -> float:
    """Helper to parse flash point, handling N/A."""
    v = str(value).strip().lower()
    if 'n/a' in v or 'none' in v or v == '':
        return -999.0  # Sentinel for N/A
    try:
        # Extract first number found
        import re
        match = re.search(r'-?\d+(\.\d+)?', v)
        if match:
            return float(match.group())
        return -999.0
    except:
        return -999.0

def verify_museum_audit(traj, env_info, task_info):
    """
    Verify the museum conservation hazard audit CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/conservation_safety_audit.csv')

    # Load export result summary
    task_result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence and anti-gaming
    if not task_result.get('output_file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task session (anti-gaming check failed)."}

    # Retrieve and parse the CSV content
    score = 0
    feedback = []
    
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(output_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            # Check headers
            required_headers = {'Chemical', 'Flash_Point_F', 'Spontaneous_Combustion_Risk', 'Is_Oxidizer'}
            if not reader.fieldnames:
                return {"passed": False, "score": 10, "feedback": "CSV file is empty."}
                
            headers = set(h.strip() for h in reader.fieldnames)
            missing_headers = required_headers - headers
            if missing_headers:
                feedback.append(f"Missing headers: {', '.join(missing_headers)}")
            else:
                score += 10
                feedback.append("CSV structure correct.")

            # Validate Content
            found_chemicals = 0
            correct_spontaneous = 0
            correct_oxidizer = 0
            correct_flashpoint = 0
            
            # Create a lookup map for the user's rows based on Chemical name
            user_data = {}
            for row in rows:
                name = row.get('Chemical', '').lower()
                user_data[name] = row

            for expected in expected_chemicals:
                exp_name_key = expected['name'].lower()
                # Fuzzy match for names
                match = None
                for user_key in user_data:
                    if exp_name_key in user_key or user_key in exp_name_key:
                        match = user_data[user_key]
                        break
                
                if match:
                    found_chemicals += 1
                    
                    # Check Spontaneous Combustion
                    user_spon = parse_bool(match.get('Spontaneous_Combustion_Risk', 'false'))
                    if user_spon == expected['spontaneous']:
                        correct_spontaneous += 1
                    else:
                        feedback.append(f"{expected['name']}: Incorrect Spontaneous Risk (Expected {expected['spontaneous']})")

                    # Check Oxidizer
                    user_ox = parse_bool(match.get('Is_Oxidizer', 'false'))
                    if user_ox == expected['oxidizer']:
                        correct_oxidizer += 1
                    else:
                        feedback.append(f"{expected['name']}: Incorrect Oxidizer status (Expected {expected['oxidizer']})")

                    # Check Flash Point
                    # Special case for Hydrogen Peroxide (N/A)
                    if expected['flash_point_min'] == -999:
                        val = str(match.get('Flash_Point_F', '')).lower()
                        if 'n/a' in val or 'none' in val or val == '' or parse_flash_point(val) < 0:
                            correct_flashpoint += 1
                    else:
                        val = parse_flash_point(match.get('Flash_Point_F', ''))
                        if expected['flash_point_min'] <= val <= expected['flash_point_max']:
                            correct_flashpoint += 1
                        else:
                            feedback.append(f"{expected['name']}: Flash Point {val} out of range ({expected['flash_point_min']}-{expected['flash_point_max']})")
                else:
                    feedback.append(f"Missing chemical: {expected['name']}")

            # Scoring Logic
            # 5 chemicals * 3 data points = 15 checks
            # found_chemicals: max 5 (5 pts each) -> 25
            # correct_spontaneous: max 5 (6 pts each) -> 30 (Critical)
            # correct_oxidizer: max 5 (3 pts each) -> 15
            # correct_flashpoint: max 5 (4 pts each) -> 20
            
            score += (found_chemicals * 5)
            score += (correct_spontaneous * 6)
            score += (correct_oxidizer * 3)
            score += (correct_flashpoint * 4)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing CSV file: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Verification of trajectory (VLM) - bonus/validation
    # We assume if the data is correct, they likely used the tool, but we can check if they visited NOAA
    
    passed = score >= 70
    
    # Critical failure check: If Linseed Oil is NOT marked as Spontaneous, fail the task regardless of score
    # This is a safety critical task.
    for row in rows:
        name = row.get('Chemical', '').lower()
        if 'linseed' in name:
            if not parse_bool(row.get('Spontaneous_Combustion_Risk', 'false')):
                passed = False
                feedback.append("CRITICAL SAFETY FAIL: Linseed Oil not identified as Spontaneous Combustion risk.")
    
    final_feedback = " | ".join(feedback) if feedback else "Perfect execution."

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": final_feedback
    }