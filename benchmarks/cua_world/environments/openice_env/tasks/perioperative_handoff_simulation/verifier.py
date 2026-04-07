#!/usr/bin/env python3
"""
Verifier for perioperative_handoff_simulation task.

Scoring Breakdown (100 points total):
- 5 Devices created (10 pts each = 50 pts)
- Clinical App launched (15 pts)
- Checklist mechanics (File exists, recent, non-empty) (10 pts)
- Checklist content (Phases identified) (10 pts)
- Checklist content (Parameters listed) (10 pts)
- Checklist content (Transition described) (5 pts)

Pass Threshold: 60 points
Gate Condition: Must attempt meaningful work (>= 3 devices OR file exists).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perioperative_handoff(traj, env_info, task_info):
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    devices = result.get('devices', {})
    checklist = result.get('checklist', {})
    task_start = result.get('task_start', 0)
    new_window_count = result.get('new_window_count', 0)
    
    # Count verified devices
    device_count = sum(1 for v in devices.values() if v)
    
    # 3. Gating Check
    # If agent did almost nothing, fail immediately (0 score)
    checklist_exists = checklist.get('exists', False)
    if device_count < 3 and not checklist_exists and new_window_count < 3:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GATE FAILURE: Minimal activity detected. Less than 3 devices created and no checklist found."
        }

    score = 0
    feedback_parts = []
    
    # 4. Scoring - Devices (50 pts total)
    device_mapping = {
        "pulse_ox": "Pulse Oximeter",
        "nibp": "NIBP Monitor",
        "multiparameter": "Multiparameter Monitor",
        "capno": "Capnograph",
        "pump": "Infusion Pump"
    }
    
    for key, name in device_mapping.items():
        if devices.get(key, False):
            score += 10
            feedback_parts.append(f"[+10] Created {name}")
        else:
            feedback_parts.append(f"[0] Missing {name}")

    # 5. Scoring - Clinical App (15 pts)
    if result.get('app_launched', False):
        score += 15
        feedback_parts.append("[+15] Clinical App launched")
    else:
        feedback_parts.append("[0] Clinical App not detected")

    # 6. Scoring - Checklist Mechanics (10 pts)
    # File must exist, be created AFTER task start, and have content
    file_valid = False
    if checklist.get('exists', False):
        mtime = checklist.get('mtime', 0)
        size = checklist.get('size_bytes', 0)
        if mtime > task_start and size >= 100:
            score += 10
            feedback_parts.append("[+10] Checklist file created validly")
            file_valid = True
        else:
            feedback_parts.append(f"[0] Checklist invalid (Size: {size}, New: {mtime > task_start})")
    else:
        feedback_parts.append("[0] Checklist file missing")

    # 7. Scoring - Checklist Content (25 pts total)
    if file_valid:
        if checklist.get('has_phases', False):
            score += 10
            feedback_parts.append("[+10] Checklist identifies Pre-Op and OR phases")
        else:
            feedback_parts.append("[0] Checklist missing phase structure")
            
        if checklist.get('has_params', False):
            score += 10
            feedback_parts.append("[+10] Checklist lists physiological parameters")
        else:
            feedback_parts.append("[0] Checklist missing parameter details")
            
        if checklist.get('has_transition', False):
            score += 5
            feedback_parts.append("[+5] Checklist describes transition")
        else:
            feedback_parts.append("[0] Checklist missing transition notes")

    # 8. Final Verdict
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "device_count": device_count,
            "checklist_valid": file_valid,
            "raw_devices": devices
        }
    }