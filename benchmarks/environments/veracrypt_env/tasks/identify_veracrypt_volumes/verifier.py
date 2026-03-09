#!/usr/bin/env python3
"""
Verifier for forensic_identification task.

Checks:
1. Report file exists and was created during the task.
2. All 8 files are correctly classified (Volume vs Not Volume).
3. Encryption and Hash algorithms are correct for volumes.
4. Correct passwords are identified for volumes.
5. No volumes are left mounted.
"""

import json
import tempfile
import os
import logging
import base64
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_veracrypt_volumes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth Data
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    gt_volumes = ground_truth.get('volumes', {})
    gt_not_volumes = ground_truth.get('not_volumes', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Check Report Existence & Timestamp (5 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Forensic report file not found"}
    
    report_mtime = result.get('report_mtime', 0)
    task_start = result.get('task_start_time', 0)
    if report_mtime < task_start:
        return {"passed": False, "score": 0, "feedback": "Report file predates task start (Anti-gaming)"}
    
    score += 5
    feedback_parts.append("Report exists")

    # Decode Report Content
    try:
        report_text = base64.b64decode(result.get('report_content_b64', '')).decode('utf-8', errors='ignore')
    except Exception:
        return {"passed": False, "score": 5, "feedback": "Failed to decode report content"}

    # 2. Check File Classification (5 pts if all files mentioned)
    all_files = list(gt_volumes.keys()) + gt_not_volumes
    mentioned_files = [f for f in all_files if f in report_text]
    
    if len(mentioned_files) == len(all_files):
        score += 5
        feedback_parts.append("All files analyzed")
    else:
        feedback_parts.append(f"Missing files in report: {len(all_files) - len(mentioned_files)}")

    # 3. Analyze Volume Identifications (8 pts each correct ID)
    # Expected format: VOLUME: <file> | ...
    # Expected format: NOT_VOLUME: <file>
    
    # Normalize report text for easier regex
    # Remove empty lines
    lines = [l.strip() for l in report_text.splitlines() if l.strip()]
    
    # Verify Volumes
    correct_volumes = 0
    correct_algos = 0
    correct_hashes = 0
    correct_passwords = 0
    
    for vol_file, details in gt_volumes.items():
        # Find line for this volume
        # Regex looks for "VOLUME:.*filename" case insensitive
        vol_pattern = re.compile(f"VOLUME:.*{re.escape(vol_file)}", re.IGNORECASE)
        match = next((l for l in lines if vol_pattern.search(l)), None)
        
        if match:
            score += 8
            correct_volumes += 1
            
            # Check Encryption (5 pts)
            if details['encryption'].lower() in match.lower():
                score += 5
                correct_algos += 1
            
            # Check Hash (3 pts)
            if details['hash'].lower() in match.lower():
                score += 3
                correct_hashes += 1
                
            # Check Password (5 pts)
            # Escape regex special chars in password if any
            if details['password'] in match:
                score += 5
                correct_passwords += 1
        else:
            feedback_parts.append(f"Failed to identify volume: {vol_file}")

    # Verify Non-Volumes (4 pts each)
    correct_non_volumes = 0
    for nv_file in gt_not_volumes:
        # Regex looks for "NOT_VOLUME:.*filename"
        nv_pattern = re.compile(f"NOT_VOLUME:.*{re.escape(nv_file)}", re.IGNORECASE)
        if any(nv_pattern.search(l) for l in lines):
            score += 4
            correct_non_volumes += 1
        else:
            # Also acceptable if listed but not marked as VOLUME? No, explicit classification required.
            pass

    # 4. Check Cleanup (5 pts)
    if not result.get('left_mounted', False):
        score += 5
        feedback_parts.append("Cleaned up mounts")
    else:
        feedback_parts.append("Volumes left mounted")

    # Generate summary feedback
    feedback_parts.append(f"Volumes ID: {correct_volumes}/4")
    feedback_parts.append(f"Non-Volumes ID: {correct_non_volumes}/4")
    if correct_algos < 4: feedback_parts.append(f"Encryption Algos: {correct_algos}/4")
    if correct_passwords < 4: feedback_parts.append(f"Passwords: {correct_passwords}/4")

    passed = score >= 60 and correct_volumes >= 3 and correct_non_volumes >= 3

    return {
        "passed": passed,
        "score": min(score, 100), # Cap at 100 just in case
        "feedback": " | ".join(feedback_parts)
    }