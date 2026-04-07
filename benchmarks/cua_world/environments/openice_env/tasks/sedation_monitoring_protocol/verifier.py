#!/usr/bin/env python3
"""
Verifier for sedation_monitoring_protocol task in OpenICE.

Scoring Breakdown (100 pts):
- Devices Created (32 pts): Multiparameter (10), Capno (12), PulseOx (10)
- App Launched (10 pts): Vital Signs app
- Interaction Evidence (8 pts): Significant window increase (devices + app + detail view)
- Protocol File (50 pts):
  - Validity (10): Exists, size > 300b, created after start
  - Content (40): 5 sections (8 pts each) + ASA ref (bonus points integrated)

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_sedation_protocol(traj, env_info, task_info):
    # 1. Setup access to result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 2. Extract Data
    score = 0
    feedback = []
    
    task_start = result.get('task_start_timestamp', 0)
    
    # Device Creation
    mp_created = result.get('multiparam_created', 0)
    co2_created = result.get('capno_created', 0)
    pox_created = result.get('pulseox_created', 0)
    total_devices = mp_created + co2_created + pox_created
    
    # App & Window Interaction
    app_launched = result.get('app_launched', 0)
    win_increase = result.get('window_increase', 0)
    
    # File Checks
    file_exists = result.get('file_exists', 0)
    file_size = result.get('file_size', 0)
    file_mtime = result.get('file_mtime', 0)
    
    # 3. Gate Condition: "Do Nothing" check
    # If < 2 devices created AND no/tiny file -> Fail immediately
    if total_devices < 2 and (not file_exists or file_size < 50):
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Minimal interaction detected. Please create required devices and write protocol.",
        }

    # 4. Scoring Logic
    
    # A. Devices (32 pts)
    if mp_created: 
        score += 10
        feedback.append("Multiparameter monitor created")
    else:
        feedback.append("Multiparameter monitor MISSING")
        
    if co2_created: 
        score += 12 # Higher weight for capnography (critical for sedation)
        feedback.append("Capnography device created")
    else:
        feedback.append("Capnography device MISSING")

    if pox_created: 
        score += 10
        feedback.append("Pulse Oximeter created")
    else:
        feedback.append("Pulse Oximeter MISSING")

    # B. App & Interaction (18 pts)
    if app_launched:
        score += 10
        feedback.append("Vital Signs app launched")
    
    # Expect 3 devices + 1 app + 1 detail view = ~5 windows
    if win_increase >= 4:
        score += 8
        feedback.append(f"Significant window interaction (+{win_increase})")
    elif win_increase >= 2:
        score += 4
        feedback.append(f"Moderate window interaction (+{win_increase})")

    # C. Protocol Document (50 pts)
    # Validity check (10 pts)
    valid_file = False
    if file_exists:
        if file_mtime > task_start and file_size >= 300:
            score += 10
            valid_file = True
            feedback.append(f"Protocol file valid ({file_size} bytes)")
        elif file_mtime <= task_start:
            feedback.append("Protocol file predates task start (Anti-Gaming)")
        else:
            score += 5
            feedback.append(f"Protocol file exists but too short ({file_size} bytes)")
    else:
        feedback.append("Protocol file NOT found")

    # Content check (40 pts)
    if valid_file:
        sections = [
            ('has_req_section', "Monitoring Requirements", 8),
            ('has_config_section', "Device Configuration", 8),
            ('has_checklist_section', "Pre-Procedure Checklist", 8),
            ('has_alarm_section', "Alarm Thresholds", 8),
            ('has_emergency_section', "Emergency Response", 5),
            ('has_asa_ref', "ASA Guideline Ref", 3)
        ]
        
        for key, name, pts in sections:
            if result.get(key, 0):
                score += pts
                feedback.append(f"Section '{name}' found")
            else:
                feedback.append(f"Section '{name}' MISSING")

    # 5. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }